//
//  FormatToAttributedString.h
//  HTMLFastParse
//
//  Created by Salman Husain on 4/28/18.
//  Copyright © 2018 CarbonDev. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface FormatToAttributedString : NSObject
-(NSAttributedString *)attributedStringForHTML:(NSString *)htmlInput;
-(void)setDefaultFontColor:(UIColor *)defaultColor;
@end
