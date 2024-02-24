//
//  MediaMetaData_TagLib.m
//  PlayEm
//
//  Created by Till Toenshoff on 24.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#include "tag_c/tag_c.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import "MediaMetaData.h"
#import "MediaMetaData+TagLib.h"

@implementation MediaMetaData(TagLib)

+ (NSArray<NSString*>*)mp3SupportedMediaDataKeys
{
    NSDictionary<NSString*, NSDictionary*>* mediaMetaKeyMap = [MediaMetaData mediaMetaKeyMap];
    NSMutableArray<NSString*>* supportedKeys = [NSMutableArray array];
    for (NSString* key in [MediaMetaData mediaMetaKeys]) {
        if ([mediaMetaKeyMap[key] objectForKey:kMediaMetaDataMapKeyMP3]) {
            [supportedKeys addObject:key];
        }
    }
    return supportedKeys;
}

+ (NSDictionary<NSString*, NSDictionary<NSString*, NSString*>*>*)mp3TagMap
{
    NSDictionary<NSString*, NSDictionary*>* mediaMetaKeyMap = [MediaMetaData mediaMetaKeyMap];
    
    NSMutableDictionary<NSString*, NSMutableDictionary<NSString*, id>*>* mp3TagMap = [NSMutableDictionary dictionary];
    
    for (NSString* mediaDataKey in [mediaMetaKeyMap allKeys]) {
        // Skip anything that isnt supported by MP3 / ID3.
        if ([mediaMetaKeyMap[mediaDataKey] objectForKey:kMediaMetaDataMapKeyMP3] == nil) {
            continue;
        }

        NSString* mp3Key = mediaMetaKeyMap[mediaDataKey][kMediaMetaDataMapKeyMP3][kMediaMetaDataMapKeyKey];
        NSString* type = mediaMetaKeyMap[mediaDataKey][kMediaMetaDataMapKeyMP3][kMediaMetaDataMapKeyType];

        NSMutableDictionary* mp3Dictionary = mp3TagMap[mp3Key];
        if (mp3TagMap[mp3Key] == nil) {
            mp3Dictionary = [NSMutableDictionary dictionary];
        }
        mp3Dictionary[kMediaMetaDataMapKeyType] = type;
        
        NSMutableArray* mediaKeys = mp3Dictionary[kMediaMetaDataMapKeyKeys];
        if (mediaKeys == nil) {
            mediaKeys = [NSMutableArray array];
            if ([type isEqualToString:kMediaMetaDataMapTypeNumbers]) {
                [mediaKeys addObjectsFromArray:@[@"", @""]];
            }
        }
        
        NSNumber* position = mediaMetaKeyMap[mediaDataKey][kMediaMetaDataMapKeyMP3][kMediaMetaDataMapKeyOrder];
        if (position != nil) {
            [mediaKeys replaceObjectAtIndex:[position intValue] withObject:mediaDataKey];
        } else {
            [mediaKeys addObject:mediaDataKey];
        }

        mp3Dictionary[kMediaMetaDataMapKeyKeys] = mediaKeys;

        mp3TagMap[mp3Key] = mp3Dictionary;
    }

    return mp3TagMap;
}

+ (MediaMetaData*)mediaMetaDataFromMP3FileWithURL:(NSURL*)url error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];
    meta.location = [url filePathURL];
    meta.locationType = [NSNumber numberWithUnsignedInteger:MediaMetaDataLocationTypeFile];

    if ([meta readFromMP3FileWithError:error] != 0) {
        return nil;
    }
    
    return meta;
}

- (int)readFromMP3FileWithError:(NSError**)error
{
    NSString* path = [self.location path];
    
    TagLib_File* file = taglib_file_new([path cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
    if (file == NULL) {
        NSString* description = @"Cannot load file using tagLib";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey: description,
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        NSLog(@"error: %@", description);
        
        return -1;
    }
    
    NSDictionary* mp3TagMap = [MediaMetaData mp3TagMap];
    
    char** propertiesMap = taglib_property_keys(file);
    if (propertiesMap != NULL) {
        char** keyPtr = propertiesMap;
        keyPtr = propertiesMap;
        
        while (*keyPtr) {
            char** propertyValues = taglib_property_get(file, *keyPtr);
            char** valPtr = propertyValues;
            
            while (valPtr && *valPtr) {
                NSString* key = [NSString stringWithCString:*keyPtr
                                                   encoding:NSStringEncodingConversionAllowLossy];
                NSString* values = [NSString stringWithCString:*valPtr
                                                      encoding:NSStringEncodingConversionAllowLossy];
                NSDictionary* map = mp3TagMap[key];
                if (map == nil) {
                    NSLog(@"ignoring unsupported ID3 tag key: %@ with value(s) \"%@\"", key, values);
                } else {
                    NSString* type = map[kMediaMetaDataMapKeyType];
                    
                    if ([type isEqualToString:kMediaMetaDataMapTypeString]) {
                        [self updateWithKey:map[kMediaMetaDataMapKeyKeys][0] string:values];
                    } else if ([type isEqualToString:kMediaMetaDataMapTypeNumbers]) {
                        NSArray<NSString*>* components = [values componentsSeparatedByString:@"/"];
                        [self updateWithKey:map[kMediaMetaDataMapKeyKeys][0] string:components[0]];
                        if ([components count] > 1) {
                            [self updateWithKey:map[kMediaMetaDataMapKeyKeys][1] string:components[1]];
                        }
                    } else if ([type isEqualToString:kMediaMetaDataMapTypeDate]) {
                        if (![values containsString:@"-"]) {
                            [self updateWithKey:map[kMediaMetaDataMapKeyKeys][0] string:values];
                        } else {
                            NSArray<NSString*>* components = [values componentsSeparatedByString:@"-"];
                            [self updateWithKey:map[kMediaMetaDataMapKeyKeys][0] string:components[0]];
                        }
                    } else if ([type isEqualToString:kMediaMetaDataMapTypeImage]) {
                        NSLog(@"skipping complex image type in simple parser");
                    } else {
                        NSAssert(NO, @"unknown type %@", type);
                    }
                }
                ++valPtr;
            };
            taglib_property_free(propertyValues);
            ++keyPtr;
        };
        taglib_property_free(propertiesMap);
    }
    
    char** complexKeys = taglib_complex_property_keys(file);
    if (complexKeys != NULL) {
        char** keyPtr = complexKeys;

        while (*keyPtr) {
            TagLib_Complex_Property_Attribute*** props = taglib_complex_property_get(file, *keyPtr);
            if (props != NULL) {
                TagLib_Complex_Property_Attribute*** propPtr = props;

                while (*propPtr) {
                    TagLib_Complex_Property_Attribute** attrPtr = *propPtr;
                    NSString* key = [NSString stringWithCString:*keyPtr
                                                       encoding:NSStringEncodingConversionAllowLossy];
                    // NOTE: We only use the first PICTURE gathered.
                    if ([key isEqualToString:@"PICTURE"] && self.artwork == nil) {

                        while (*attrPtr) {
                            TagLib_Complex_Property_Attribute* attr = *attrPtr;
                            TagLib_Variant_Type type = attr->value.type;
                            if (type == TagLib_Variant_ByteVector) {
                                NSData* data = [NSData dataWithBytes:attr->value.value.byteVectorValue
                                                              length:attr->value.size];
                                NSLog(@"updated artwork with %ld bytes of image data", [data length]);
                                self.artwork = [[NSImage alloc] initWithData:data];
                            }
                            ++attrPtr;
                        };
                    }
                    ++propPtr;
                };
                taglib_complex_property_free(props);
            }
            ++keyPtr;
        };
        taglib_complex_property_free_keys(complexKeys);
    }
    
    taglib_tag_free_strings();
    taglib_file_free(file);
    
    return 0;
}

// Note that we are avoiding using `BOOL` in the signature here as that gets defined as `int`
// by "taglib_c.h". Trouble is, Objective C typedefs BOOL to various types, depending on the
// platform and processor architecture. See
// https://www.jviotti.com/2024/01/05/is-objective-c-bool-a-boolean-type-it-depends.html
- (int)writeToMP3FileWithError:(NSError**)error
{
    NSString* path = [self.location path];
    
    TagLib_File* file = taglib_file_new([path cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
    
    if (file == NULL) {
        NSString* description = @"Cannot open file using tagLib";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey: description,
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        NSLog(@"error: %@", description);
        
        return -1;
    }
    
    NSDictionary* mp3TagMap = [MediaMetaData mp3TagMap];
    
    for (NSString* mp3Key in [mp3TagMap allKeys]) {
        NSString* type = mp3TagMap[mp3Key][kMediaMetaDataMapKeyType];
        
        if ([type isEqualToString:kMediaMetaDataMapTypeImage]) {
            NSLog(@"setting image data not yet supported");
        } else {
            NSString* mediaKey = mp3TagMap[mp3Key][kMediaMetaDataMapKeyKeys][0];
            NSString* value = [self stringForKey:mediaKey];
            
            if ([type isEqualToString:kMediaMetaDataMapTypeNumbers]) {
                NSMutableArray* components = [NSMutableArray array];
                [components addObject:value];
                
                NSString* mediaKey2 = mp3TagMap[mp3Key][kMediaMetaDataMapKeyKeys][1];
                NSString* value2 = [self stringForKey:mediaKey2];
                if ([value2 length] > 0) {
                    [components addObject:value2];
                }
                value = [components componentsJoinedByString:@"/"];
            }
            // NOTE: We are possible reducing the accuracy of a DATE as we will only store the year
            // while the original may have had day and month included.
            
            NSLog(@"setting ID3: \"%@\" = \"%@\"", mp3Key, value);
            taglib_property_set(file,
                                [mp3Key cStringUsingEncoding:NSStringEncodingConversionAllowLossy],
                                [value cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
        }
    }
    
    int ret = 0;
    
    if (!taglib_file_save(file)) {
        NSString* description = @"Cannot store file using tagLib";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey: description,
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        NSLog(@"error: %@", description);
        ret = -1;
    }
    
    taglib_tag_free_strings();
    taglib_file_free(file);
    
    return ret;
}

@end