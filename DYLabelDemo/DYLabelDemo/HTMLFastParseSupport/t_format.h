//
//  t_format.h
//  HTMLFastParse
//
//  Created by Salman Husain on 4/27/18.
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
	char* linkURL;
	
	unsigned int startPosition;
	unsigned int endPosition;
};

#endif /* t_format_h */
