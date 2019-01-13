//
//  FormatToAttributedString.m
//  HTMLFastParse
//
//  Created by Salman Husain on 4/28/18.
//  Copyright © 2018 CarbonDev. All rights reserved.
//

#import "FormatToAttributedString.h"
#import "C_HTML_Parser.h"
#import <UIKit/UIKit.h>

@implementation FormatToAttributedString
NSString *standardFontName;
NSString *boldFontName;
NSString *italicFontName;
NSString *italicsBoldFontName;
NSString *codeFontName;

UIFont *plainFont;
UIFont *boldFont;
UIFont *italicsFont;
UIFont *italicsBoldFont;
UIFont *codeFont;


UIColor *defaultFontColor;
UIColor *codeFontColor;
UIColor *containerBackgroundColor;
UIColor *quoteFontColor;

//We pregenerate nested quotes up to four for speed, after that they're dynamically allocated
NSMutableParagraphStyle *quoteParagraphStyle1;
NSMutableParagraphStyle *quoteParagraphStyle2;
NSMutableParagraphStyle *quoteParagraphStyle3;
NSMutableParagraphStyle *quoteParagraphStyle4;
NSMutableParagraphStyle *defaultParagraphStyle;

//The most basic text font size
CGFloat baseFontSize;

float quotePadding = 20.0;


/**
 Create a new Formatter
 
 @return self
 */
-(id)init {
    self = [super init];
    //Configure out colors
    codeFontColor = [UIColor colorWithRed:255.0/255 green:0 blue:255.0/255 alpha:1];
    containerBackgroundColor = [UIColor colorWithRed:242.0/255 green:242.0/255 blue:242.0/255 alpha:1];
    quoteFontColor = [UIColor colorWithRed:119.0/255 green:119.0/255 blue:119.0/255 alpha:1];
    defaultFontColor = [UIColor blackColor];
    
    //Prepare our common fonts once
    standardFontName = @"Avenir-Light";
    boldFontName = @"Avenir-Heavy";
    italicFontName = @"Avenir-BookOblique";
    italicsBoldFontName = @"Avenir-HeavyOblique";
    codeFontName = @"CourierNewPSMT";
    [self prepareFonts];
    return self;
}


/**
 Initilize and cache high frquency fonts, colors, and other styles
 */
-(void)prepareFonts {
    //Get the user's prefered fontsize from the system and use that as the base
    baseFontSize = [UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize;
    
    plainFont = [UIFont fontWithName:standardFontName size:baseFontSize];
    boldFont = [UIFont fontWithName:boldFontName size:baseFontSize];
    italicsFont = [UIFont fontWithName:italicFontName size:baseFontSize];
    italicsBoldFont = [UIFont fontWithName:italicsBoldFontName size:baseFontSize];
    codeFont = [UIFont fontWithName:codeFontName size:baseFontSize];
    
    //Cache high frequency quote depths (1-4), after these they'll be dynamically generated
    quoteParagraphStyle1 = [self generateParagraphStyleAtLevel:1];
    quoteParagraphStyle2 = [self generateParagraphStyleAtLevel:2];
    quoteParagraphStyle3 = [self generateParagraphStyleAtLevel:3];
    quoteParagraphStyle4 = [self generateParagraphStyleAtLevel:4];
    defaultParagraphStyle = [self defaultParagraphStyle];
}


/**
 Override the default font text color (by default this is black). This only needs to be called once
 
 @param defaultColor The color to change it to
 */
-(void)setDefaultFontColor:(UIColor *)defaultColor {
    defaultFontColor = defaultColor;
}


/**
 Generate an indented "style"
 This is used for quote formatting
 
 @param depth The depth * `quotePadding` is the amount of indent that will be used. Zero means no indent
 @return A paragraph style object usuable in attribution
 */
-(NSMutableParagraphStyle *)generateParagraphStyleAtLevel:(int)depth {
    NSMutableParagraphStyle *quoteParagraphStyle = [[NSMutableParagraphStyle alloc]init];
    CGFloat levelQuoteIndentPadding = quotePadding * depth;
    [quoteParagraphStyle setParagraphSpacing:plainFont.lineHeight/4];
    [quoteParagraphStyle setHeadIndent:levelQuoteIndentPadding];
    [quoteParagraphStyle setFirstLineHeadIndent:levelQuoteIndentPadding];
    [quoteParagraphStyle setTailIndent:-levelQuoteIndentPadding];
    return quoteParagraphStyle;
}


/**
 Generate the default paragraph style which should be applied to all text
 
 @return Default paragraph style
 */
-(NSMutableParagraphStyle *)defaultParagraphStyle {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc]init];
    [style setParagraphSpacing:plainFont.lineHeight/4];
    
    return style;
}


/**
 Attribute a string of HTML using HTMLFastParse
 
 @param htmlInput The HTML to attribute
 @return The attributed string
 */
-(NSAttributedString *)attributedStringForHTML:(NSString *)htmlInput {
    char* input = (char*)[htmlInput UTF8String];
    if (input == nil) {
        //Input can be null if htmlInput is also null or if it is not representable in UTF8. We are not going to bother parsing data which requires > 8bits per field because it can't fit in a char
        return [[NSAttributedString alloc]initWithString:@"[HTMLFastParse Internal Error]: Either no data was sent to the parser or the data could not be decoded by the system. Please verify the API is being used correctly or report this at https://github.com/shusain93/HTMLFastParse/issues"];
    }
    unsigned long inputLength = strlen(input);
    
    char* displayText = malloc(inputLength * sizeof(char) + 1); //+1 for a null byte
    struct t_tag* tokens = malloc(inputLength * sizeof(struct t_tag));
    
    int numberOfTags = -1;
    int numberOfHumanVisibleCharachters = -1;
    tokenizeHTML(input, inputLength, displayText,tokens,&numberOfTags,&numberOfHumanVisibleCharachters);
    
    struct t_format* finalTokens =  malloc(inputLength * sizeof(struct t_format));//&finalTokenBuffer[0];
    int numberOfSimplifiedTags = -1;
    makeAttributesLinear(tokens, (int)numberOfTags, finalTokens,&numberOfSimplifiedTags,numberOfHumanVisibleCharachters);
    
    //Now apply our linear attributes to our attributed string
    NSMutableAttributedString *answer = [[NSMutableAttributedString alloc]initWithString:[NSString stringWithUTF8String:displayText]];
    
    //Add our default attributes
    [answer addAttributes:@{
                            NSFontAttributeName : plainFont,
                            NSParagraphStyleAttributeName : defaultParagraphStyle,
                            NSBackgroundColorAttributeName : [UIColor clearColor]
                            } range:NSMakeRange(0, answer.length)];
    //Only format the string if we are sure that everything will line up (if our calculated visible is not the same as attributed sees, everything will be broken and likely will cause a crash
    if ([answer length] == numberOfHumanVisibleCharachters) {
        for (int i = 0; i < numberOfSimplifiedTags; i++) {
            [self addAttributeToString:answer forFormat:finalTokens[i]];
            free(finalTokens[i].linkURL);
        }
    }else {
        NSAttributedString *failureText = [[NSAttributedString alloc]initWithString:@"\n\n\n[HTMLFastParse Internal Error]: HFP detected an issue where NSAttributedString length and the calculated visible length are not equal. Please report this at https://github.com/shusain93/HTMLFastParse/issues"];
        [answer appendAttributedString: failureText];
    }
    
    //Free and get ready to return
    free(displayText);
    free(tokens);
    free(finalTokens);
    return answer;
}


/**
 Add the attributes to a given attributed string based on a t_format specifier
 
 @param string The mutable attributed string to work on
 @param format The styles to apply (with range data stuffed!)
 */
-(void)addAttributeToString:(NSMutableAttributedString *)string forFormat:(struct t_format)format {
    //This is the range of the style
    NSRange currentRange = NSMakeRange(format.startPosition, format.endPosition-format.startPosition);
    
    if (format.linkURL) {
        NSString *nsLinkURL = [NSString stringWithUTF8String:format.linkURL];
        if ([NSURL URLWithString:nsLinkURL] != nil) {
            [string addAttribute:NSLinkAttributeName value: nsLinkURL range:currentRange];
        }
    }
    
    if (format.isStruck) {
        [string addAttribute:NSStrikethroughStyleAttributeName value:[NSNumber numberWithInteger:NSUnderlineStyleSingle] range:currentRange];
    }
    
    if (format.quoteLevel > 0) {
        NSMutableParagraphStyle *quoteParagraphStyle;
        //We have the first four cached and after that we'll dynamically generate
        switch (format.quoteLevel) {
            case 1:
                quoteParagraphStyle = quoteParagraphStyle1;
                break;
            case 2:
                quoteParagraphStyle = quoteParagraphStyle2;
                break;
            case 3:
                quoteParagraphStyle = quoteParagraphStyle3;
                break;
            case 4:
                quoteParagraphStyle = quoteParagraphStyle4;
                break;
                
            default:
                quoteParagraphStyle = [self generateParagraphStyleAtLevel:format.quoteLevel];
                break;
        }
        [string addAttribute:NSParagraphStyleAttributeName value:quoteParagraphStyle range:currentRange];
        [string addAttribute:NSForegroundColorAttributeName value:quoteFontColor range:currentRange];
    }
    
    
    
    /* Styling that uses fonts. This includes exponents, h#, bold, italics, and any combination thereof. Code formatting skips all of these */
    
    if (format.isCode == 1) {
        [string addAttribute:NSFontAttributeName value:codeFont range:currentRange];
        [string addAttribute:NSBackgroundColorAttributeName value:containerBackgroundColor range:currentRange];
        [string addAttribute:NSForegroundColorAttributeName value:codeFontColor range:currentRange];
    }
    //Check if we can take a shortcut. We don't need dynamic font in this case
    else if (format.hLevel == 0 && format.exponentLevel == 0) {
        if (format.isBold == 0 && format.isItalics == 0) {
            //Plain text
            //Do nothing since it's the default as set above
        }else if (format.isBold == 1 && format.isItalics == 1) {
            //Bold italics
            [string addAttribute:NSFontAttributeName value:italicsBoldFont range:currentRange];
        }else if (format.isBold == 1) {
            //Bold
            [string addAttribute:NSFontAttributeName value:boldFont range:currentRange];
        }else if (format.isItalics == 1) {
            //Italics
            [string addAttribute:NSFontAttributeName value:italicsFont range:currentRange];
        }
    }else {
        //We need to generate a dynamic font since at least one of the attributes changes the font size.
        CGFloat fontSize = baseFontSize;
        //Handle H#
        if (format.hLevel > 0) {
            //Reddit only supports 1-6, so that's all that's been implmented
            switch (format.hLevel) {
                case 0:
                    break;
                case 1:
                    fontSize *= 2;
                    break;
                case 2:
                    fontSize *= 1.5;
                    break;
                case 3:
                    fontSize *= 1.17;
                    break;
                case 4:
                    fontSize *= 1.12;
                    break;
                case 5:
                    fontSize *= 0.83;
                    break;
                case 6:
                    fontSize *= 0.75;
                    break;
                default:
                    //Unexpcted position, so we're not going to apply this style
                    NSLog(@"Unknown HLevel");
                    break;
            }
        }
        //Handle exponent
        if (format.exponentLevel > 0) {
            fontSize *= 0.75;
            float baselineOffset;
            if (format.exponentLevel < 3) {
                baselineOffset = format.exponentLevel*10;
            }else {
                baselineOffset = 40;
            }
            
            [string addAttribute:NSBaselineOffsetAttributeName value:[NSNumber numberWithFloat:baselineOffset] range:currentRange];
        }
        
        
        UIFont *customFont;
        /* NOTE: USE fontWithSize: and NOT font descriptors because https://stackoverflow.com/q/34954956/1166266 */
        if (format.isBold == 0 && format.isItalics == 0) {
            //Plain text
            customFont = [plainFont fontWithSize:fontSize];
        }else if (format.isBold == 1 && format.isItalics == 1) {
            //Bold italics
            customFont = [italicsBoldFont fontWithSize:fontSize];
        }else if (format.isBold == 1) {
            //Bold
            customFont = [boldFont fontWithSize:fontSize];
        }else if (format.isItalics == 1) {
            //Italics
            customFont = [italicsFont fontWithSize:fontSize];
        }
        
        
        [string addAttribute:NSFontAttributeName value:customFont range:currentRange];
    }
    
    if (format.isCode == 0 && format.quoteLevel == 0) {
        [string addAttribute:NSForegroundColorAttributeName value:defaultFontColor range:currentRange];
    }
}
@end

