//
//  t_format.h
//  HTMLFastParse
//
//  Created by Allison Husain on 4/27/18.
//  Copyright © 2018 CarbonDev. All rights reserved.
//

#ifndef t_format_h
#define t_format_h



/**
 A structure representing a charachter/range's text formatting
 */
struct t_format {
	//ZERO MEANS DISABLED
	unsigned char isBold;
	unsigned char isItalics;
	unsigned char isStruck;
	unsigned char isCode;
	unsigned char exponentLevel;
	unsigned char quoteLevel;
	unsigned char hLevel;
    unsigned char listNestLevel;
    /*unsigned short LONG_DOUBLE_BUFFER_REMOVE2;
    unsigned short LONG_DOUBLE_BUFFER_REMOVE4;
    unsigned short LONG_DOUBLE_BUFFER_REMOVE6;
    unsigned char LONG_DOUBLE_BUFFER_REMOVE7;*/
    
	char* linkURL;
	
	unsigned int startPosition;
	unsigned int endPosition;
};

#endif /* t_format_h */
