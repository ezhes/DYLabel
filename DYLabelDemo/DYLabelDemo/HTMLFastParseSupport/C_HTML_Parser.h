//
//  C_HTML_Parser.h
//  HTMLFastParse
//
//  Created by Allison Husain on 4/27/18.
//  Copyright © 2018 CarbonDev. All rights reserved.
//

#ifndef C_HTML_Parser_h
#define C_HTML_Parser_h

#include <stdio.h>
#include "t_tag.h"
#include "t_format.h"

void tokenizeHTML(char input[],size_t inputLength,char displayText[], struct t_tag completedTags[], int* numberOfTags, int* numberOfHumanVisibleCharachters);
void makeAttributesLinear(struct t_tag inputTags[], int numberOfInputTags, struct t_format simplifiedTags[], int* numberOfSimplifiedTags, int displayTextLength);

#endif /* C_HTML_Parser_h */
