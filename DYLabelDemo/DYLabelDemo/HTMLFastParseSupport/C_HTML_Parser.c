//
//  C_HTML_Parser.c
//  HTMLFastParse
//
//  Created by Allison Husain on 4/27/18.
//  Copyright © 2018 CarbonDev. All rights reserved.
//
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <limits.h>

#include "C_HTML_Parser.h"
#include "t_tag.h"
#include "t_format.h"
#include "Stack.h"
#include "entities.h"

//Disable printf
#define printf(fmt, ...) (0)

//Enable reddit tune. Comment this out to remove them
#define reddit_mode 1;


/**
 Get the number of bytes that a given charachter will use when displayed (multi-byte unicode charachters need to be handled like this because NSString counts multi-byte chars as single charachters while C does not obviously)
 
 @param charachter The charachter
 @return A value between 0-1 if that charachter is valid
 */
int getVisibleByteEffectForCharachter(unsigned char charachter) {
	int firstHighBit = (charachter & 0x80);
	if (firstHighBit == 0x0) {
		//Regular ASCII
		return 1;
	}else {
		unsigned char secondHighBit = ((charachter << 1) & 0x80);
		if (secondHighBit == 0x0) {
			//Additional byte charachter (10xxxxxx charachter). Not visible
			return 0;
		}else {
			//This is the start of a multibyte charachter, count it (1+)
			unsigned char fourByteTest = charachter & 0b11110000;
			if (fourByteTest == 0b11110000) {
				//Patch for apple's weirdness with four byte charachters (they're counted as two visible? WHY?!?!?)
				return 2;
			}else {
				//We're multibyte but not a four byte which requires the patch, count normally
				return 1;
			}
		}
	}
}

/**
 Tockenize and extract tag info from the input and then output the cleaned string alongisde a tag array with relevant position info
 
 @param input Input text as a char array
 @param inputLength The number of charachters (as bytes) to read, excluding the null byte!
 @param displayText The char array to write the clean, display text to
 @param completedTags (returned) The array to write the t_format structs to (provides position and tag info). Tags positions are CHARACHTER relative, not byte relative! Usable in NSAttributedString etc
 @param numberOfTags (returned) The number of tags discovered
 */
void tokenizeHTML(char input[],size_t inputLength,char displayText[], struct t_tag completedTags[], int* numberOfTags, int* numberOfHumanVisibleCharachters) {
	//A stack used for processing tags. The stack size allocates space for x number of POINTERS. Ie this is not creating an overflow vulnerability AFAIK
	struct Stack* htmlTags = createStack((int)inputLength);
	//Completed / filled tags
	//struct t_format completedTags[(int)inputLength];
	int completedTagsPosition = 0;
	
	//Used to track if we are currently reading the label of an HTML tag
	bool isInTag = false;
	char *tagNameCharArray = malloc(inputLength * sizeof(char) + 1); //+1 for a null byte
	char *tagNameBuffer = &tagNameCharArray[0];//Hack to get our buffer on the stack because it's a very fast allocation
	int tagNameCopyPosition = 0;
	
	//Used to track if we are currently reading an HTML entity
	bool isInHTMLEntity = false;
	char *htmlEntityCharArray = malloc(inputLength * sizeof(char) + 1); //+1 for a null byte
	char *htmlEntityBuffer = &htmlEntityCharArray[0];//Hack to get our buffer on the stack because it's a very fast allocation
	int htmlEntityCopyPosition = 0;
	
	int stringCopyPosition = 0;
	//Used for applying tokens, DO NOT USE FOR MEMORY WORK. This is used because NSString handles multibyte charachters as single charachters and not as multiple like we have to
	int stringVisiblePosition = 0;
	
	char previous = 0x00;
    //The current index label (i.e. 1,2,3) of the list, USHRT_MAX for unordered
    unsigned short currentListValue = 0x00;
	
	for (int i = 0; i < inputLength; i++) {
		char current = input[i];
		if (current == '<') {
			isInTag = true;
			tagNameCopyPosition = 0;
			
			//If there's a next charachter (data validation) and it's NOT '/' (i.e. we're an open tag) we want to create a new formatter on the stack
			if (i+1 < inputLength && input[i+1] != '/') {
				struct t_tag format;
                format.tag = NULL;
				format.startPosition = stringVisiblePosition;
				push(htmlTags,format);
			}
			
		}else if (current == '>') {
			//We've hit an unencoded less than which terminates an HTML tag
			isInTag = false;
			//Terminate the buffer
			tagNameBuffer[tagNameCopyPosition] = 0x00;
			
			//Are we a closing HTML tag (i.e. the first character in our tag is a '/')
			if (tagNameBuffer[0] == '/') {
				//We are a closing tag, commit
                struct t_tag* formatP = pop(htmlTags);
                //Make sure we didn't get a NULL from popping an empty stack
                if (formatP != 0) {
                    struct t_tag format = *formatP;
                    format.endPosition = stringVisiblePosition;
                    completedTags[completedTagsPosition] = format;
                    completedTagsPosition++;
                }
			}
			//Are we a self closing tag like <br/> or <hr/>?
			else if ((tagNameCopyPosition > 0 && tagNameBuffer[tagNameCopyPosition-1] == '/')) {
				//These tags are special because they're an action in it of themselves so they both start themselves and commit all in one.
				struct t_tag format = *pop(htmlTags);
				
				/* special cases, take a shortcut and remove the tags */
				if (strncmp(tagNameBuffer, "br/", 3) == 0) {
					//We're a <br/> tag, drop a new line into the actual text and remove the tag
					//IGNORE THESE WHEN USING THE REDDIT MODE because Reddit already sends a new line after <br/> tags so it's duplicated in effect
#ifndef reddit_mode
					displayText[stringCopyPosition] = '\n';
					stringCopyPosition++;
					stringVisiblePosition++;
#endif
				}else {
					//We're not a known case, add the tag into the extracted tag array
					long tagNameLength = (tagNameCopyPosition + 1) * sizeof(char);
					char *newTagBuffer = malloc(tagNameLength);
					strncpy(newTagBuffer,tagNameBuffer,tagNameLength);
					
					format.tag = newTagBuffer;
					format.startPosition = stringVisiblePosition;
					format.endPosition = stringVisiblePosition;
					
					completedTags[completedTagsPosition] = format;
					completedTagsPosition++;
				}
				
				
			}else {
				//No -- so let's push the operation onto our stack
				//We've ended the tag definition, so pull the tag from the buffer and push that on to the stack
				long tagNameLength = (tagNameCopyPosition + 1) * sizeof(char);
				char *newTagBuffer = malloc(tagNameLength);
				memset(newTagBuffer, 0x0, tagNameLength);
				strncpy(newTagBuffer,tagNameBuffer,tagNameLength);
                struct t_tag* formatP = pop(htmlTags);
                //Make sure we didn't get a NULL from popping an empty stack
                //If we end up failing here the text will be horribly mangled however "broken formatting" IMHO is better than a full crash or worse a sec issue
                if (formatP != 0) {
                    struct t_tag format = *formatP;
                    format.tag = newTagBuffer;
                    push(htmlTags,format);
                }
                
                //Add textual descriptors for order/unordered lists
                if (strncmp(newTagBuffer, "ol", 2) == 0) {
                    //Ordered list
                    currentListValue = 1;
                }else if (strncmp(newTagBuffer, "ul", 2) == 0) {
                    //Unordered list
                    currentListValue = USHRT_MAX;
                }else if (strncmp(newTagBuffer, "li", 2) == 0) {
                    //Apply current list index
                    if (currentListValue == USHRT_MAX) {
                        stringVisiblePosition += 2;
                        displayText[stringCopyPosition++] = 0xE2;
                        displayText[stringCopyPosition++] = 0x80;
                        displayText[stringCopyPosition++] = 0xA2;
                        displayText[stringCopyPosition++] = ' ';
                    }else {
                        int written = sprintf(&displayText[stringCopyPosition], "%i. ",currentListValue);
                        stringCopyPosition += written;
                        stringVisiblePosition += written;
                        currentListValue++;
                    }
                }
			}
            tagNameCopyPosition = 0;
		}else if (current == '&') {
			//We are starting an HTML entitiy;
			isInHTMLEntity = true;
			htmlEntityCopyPosition = 0;
			htmlEntityBuffer[htmlEntityCopyPosition] = '&';
			htmlEntityCopyPosition++;
		}else if (isInHTMLEntity == true && current == ';') {
			//We are finishing an HTML entity
			isInHTMLEntity = false;
			htmlEntityBuffer[htmlEntityCopyPosition] = ';';
			htmlEntityCopyPosition++;
			htmlEntityBuffer[htmlEntityCopyPosition] = 0x00;
			htmlEntityCopyPosition++;
			
			//Are we decoding into a tag (i.e. into the url portion of <a href='http://test/forks?t=yes&f=no'/>
			if (isInTag) {
				//Yes!
				size_t numberDecodedBytes = decode_html_entities_utf8(&tagNameBuffer[tagNameCopyPosition], htmlEntityBuffer);
				tagNameCopyPosition += numberDecodedBytes;
			}else {
				//Expand into regular text
				size_t numberDecodedBytes = decode_html_entities_utf8(&displayText[stringCopyPosition], htmlEntityBuffer);
                for (unsigned long decodedI = 0; decodedI < numberDecodedBytes; decodedI++) {
                    //Add the visual effect for each characher. This lets us also handle when decode sends back a tag it can't decode.
                    //Also helpful incase we have codes which decode to multiple charachters, which could happen
                    stringVisiblePosition += getVisibleByteEffectForCharachter(displayText[stringCopyPosition + decodedI]);
                }
				
				stringCopyPosition += numberDecodedBytes;
			}
			
			
		}else {
			if (isInTag) {
				tagNameBuffer[tagNameCopyPosition] = current;
				tagNameCopyPosition++;
			}else if (isInHTMLEntity) {
				htmlEntityBuffer[htmlEntityCopyPosition] = current;
				htmlEntityCopyPosition++;
			}else {
				
				//Don't allow double new lines (thanks redddit for sending these?)
                //Don't allow just new lines (happens between blockquotes and p tags, again reddit issue)
				//This messes up quote formatting
#ifdef reddit_mode
				if ((current != '\n' || previous != '\n') && (current != '\n' || stringVisiblePosition > 1 )) {
#endif
					previous = current;
					displayText[stringCopyPosition] = current;
					stringVisiblePosition+=getVisibleByteEffectForCharachter(current);
					stringCopyPosition++;
#ifdef reddit_mode
				}
#endif
				
			}
		}
	}
    
    //Check if the last tag is incomplete (i.e. "blah blah <tag") so we can remove the unfinished tag from the stack
    if (tagNameCopyPosition > 0) {
        printf("!!! Found incomplete tag, popping and continuing...");
        pop(htmlTags);
    }
    
	//and now terminate our output.
	displayText[stringCopyPosition] = 0x00;
	
	//Run through the unclosed tags so we can either process them and or free them
	while (!isEmpty(htmlTags)) {
        struct t_tag* formatP = pop(htmlTags);
        //Make sure we didn't get a NULL from popping an empty stack
        if (formatP != NULL) {
            struct t_tag in = *formatP;
            printf("!!! UNCLOSED TAG: %s starts at %i ends at %i\n",in.tag,in.startPosition,in.endPosition);
            free(in.tag);
        }
	}
	
	//Now print out all tags
	
	for (int i = 0; i < completedTagsPosition; i++) {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-variable"
		struct t_tag inTag = completedTags[i];
		printf("TAG: %s starts at %i ends at %i\n",inTag.tag,inTag.startPosition,inTag.endPosition);
#pragma GCC diagnostic pop
	}
	*numberOfTags = completedTagsPosition;
	*numberOfHumanVisibleCharachters = stringVisiblePosition;
	
	//Release everything that's not necessary
	prepareForFree(htmlTags);
	free(htmlTags);
	free(tagNameCharArray);
	free(htmlEntityCharArray);
}

void print_t_format(struct t_format format) {
	printf("Format [%i,%i): Bold %i, Italic %i, Struck %i, Code %i, Exponent %i, Quote %i, H%i, ListNest %i LinkURL %s\n",format.startPosition,format.endPosition,format.isBold,format.isItalics,format.isStruck,format.isCode,format.exponentLevel,format.quoteLevel,format.hLevel,format.listNestLevel,format.linkURL);
}


/**
 Compare two t_formats. Returns 0 for the same, 1 if different in anyway
 
 @param format1 The first t_format struct
 @param format2 The second t_format struct
 @return 0 or 1
 */
int t_format_cmp(struct t_format format1,struct t_format format2) {
	//Doubles are 8 bytes, which covers all the boolean properties and a tiny bit of the link pointer
	//Tip from one of the LLVM people at WWDC`18
	double format1Sum = *(((double*)&format1.isBold));
	double format2Sum = *(((double*)&format2.isBold));
    //Get the next 8 bytes
    //double format3Sum = *((1 + (double*)&format1.isBold));
    //double format4Sum = *((1 + (double*)&format2.isBold));
	if (format1Sum != format2Sum /*|| format3Sum != format4Sum*/) {
		return 1;
	}if (format1.linkURL != format2.linkURL || ((format1.linkURL != NULL && format2.linkURL == NULL) || (format2.linkURL != NULL && format1.linkURL == NULL)) || (format1.linkURL != NULL && format2.linkURL != NULL && strcmp(format1.linkURL, format2.linkURL) != 0)) {
		return 1;
	}else {
		return 0;
	}
}


/**
 Takes in overlapping t_format tags and simplifies them into 1D range suitable for use in NSAttributedString. Destroys inputTags in the process!
 
 @param inputTags Overlapping tags buffer (given by tokenizeHTML)
 @param numberOfInputTags The number of inputTags
 @param simplifiedTags (return) Simplified tags buffer (return value)
 @param numberOfSimplifiedTags (return) the number of found simplified tags
 @param displayTextLength The size of the text that we will be applying these tags to
 */
void makeAttributesLinear(struct t_tag inputTags[], int numberOfInputTags, struct t_format simplifiedTags[], int* numberOfSimplifiedTags, int displayTextLength) {
	//Create our state array
	size_t bufferSize = displayTextLength * sizeof(struct t_format);
	struct t_format *displayTextFormat = malloc(bufferSize);
	//Init everything to zero in a single pass memory zero
	memset(displayTextFormat, 0, bufferSize);

	//Apply format from each tag
	for (int i = 0; i < numberOfInputTags; i++) {
		struct t_tag tag = inputTags[i];
		char* tagText = tag.tag;
		
		if (tagText == NULL) {
			printf("NULL TAG TEXT?? SKIPPING!");
		}else if (strncmp(tagText, "strong", 6) == 0) {
			//Apply bold to all
			for (int j = tag.startPosition; j < tag.endPosition; j++) {
				displayTextFormat[j].isBold = 1;
			}
		}else if (strncmp(tagText, "em", 2) == 0) {
			//Apply italics to all
			for (int j = tag.startPosition; j < tag.endPosition; j++) {
				displayTextFormat[j].isItalics = 1;
			}
		}else if (strncmp(tagText, "del", 3) == 0) {
			//Apply strike to all
			for (int j = tag.startPosition; j < tag.endPosition; j++) {
				displayTextFormat[j].isStruck = 1;
			}
		}else if (strncmp(tagText, "code", 4) == 0) {
			//Apply CODE! to all
			for (int j = tag.startPosition; j < tag.endPosition; j++) {
				displayTextFormat[j].isCode = 1;
			}
		}else if (strncmp(tagText, "blockquote", 10) == 0) {
			//Increase quote level
			for (int j = tag.startPosition; j < tag.endPosition; j++) {
				displayTextFormat[j].quoteLevel++;
			}
		}else if (strncmp(tagText, "sup", 3) == 0) {
			//Increase superscript level
			for (int j = tag.startPosition; j < tag.endPosition; j++) {
				displayTextFormat[j].exponentLevel++;
			}
		}else if (tagText[0] == 'h' && tagText[1] >= '1' && tagText[1] <= '6') {
			//Set our header level
			for (int j = tag.startPosition; j < tag.endPosition; j++) {
				displayTextFormat[j].hLevel = tagText[1] - '0';
			}
		}else if (strncmp(tagText, "a href=", 7) == 0) {
			//We first need to extract the link
			long tagTextLength = strlen(tagText);
			char *url = malloc(tagTextLength-7);
			//Extract the URL
			int z = 8;
			for (; z < tagTextLength; z++) {
				if (tagText[z] == '"') {
					break;
				}else {
					url[z-8] = tagText[z];
				}
			}
			url[z-8] = 0x00;
			
			//Set our link
			for (int j = tag.startPosition; j < tag.endPosition; j++) {
				displayTextFormat[j].linkURL = url;
			}
			
			//If we never got into the loop above (and so url is never stored else where), free it now.
			if (tag.endPosition - tag.startPosition <= 0) {
				free(url);
			}
			
        }else if (strncmp(tagText, "ol", 2) == 0 || (strncmp(tagText, "ul", 2) == 0)) {
            //Apply list intendation
            for (int j = tag.startPosition; j < tag.endPosition; j++) {
                displayTextFormat[j].listNestLevel++;
            }
        }
        else {
			printf("Unknown tag: %s\n",tagText);
		}
		
		
		//Destroy inputTags data as warned
		free(tag.tag);
		tag.tag = NULL;
	}
	
	for (int i = 0; i < displayTextLength; i++) {
		//print_t_format(displayTextFormat[i]);
	}
	printf("--------\n");
	
	//Now that each charachter has it's style, let's simplify to a 1D
	*numberOfSimplifiedTags = 0;
	unsigned int activeStyleStart = 0;
	for (int i = 1; i < displayTextLength; i++) {
		if (t_format_cmp(displayTextFormat[activeStyleStart], displayTextFormat[i]) != 0) {
			//We're different, so commit our previous style (with start and ends) and adopt the current one
			displayTextFormat[i-1].startPosition = activeStyleStart;
			displayTextFormat[i-1].endPosition = i;
			simplifiedTags[*numberOfSimplifiedTags] = displayTextFormat[i-1];
			
			if (displayTextFormat[i-1].linkURL) {
				simplifiedTags[*numberOfSimplifiedTags].linkURL = malloc(strlen(displayTextFormat[i-1].linkURL) + 1);
				memcpy(simplifiedTags[*numberOfSimplifiedTags].linkURL, displayTextFormat[i-1].linkURL, strlen(displayTextFormat[i-1].linkURL) + 1);
			}
			
			print_t_format(displayTextFormat[i-1]);
			*numberOfSimplifiedTags+=1;
			activeStyleStart = i;
		}
	}
	
	//and commit the final style
	//We need to make sure we have displayed text otherwise we over/underflow here
	if (displayTextLength > 0) {
		displayTextFormat[displayTextLength-1].startPosition = activeStyleStart;
		displayTextFormat[displayTextLength-1].endPosition = displayTextLength;
		simplifiedTags[*numberOfSimplifiedTags] = displayTextFormat[displayTextLength-1];
		if (displayTextFormat[displayTextLength-1].linkURL) {
			simplifiedTags[*numberOfSimplifiedTags].linkURL = malloc(strlen(displayTextFormat[displayTextLength-1].linkURL) + 1);
			memcpy(simplifiedTags[*numberOfSimplifiedTags].linkURL, displayTextFormat[displayTextLength-1].linkURL, strlen(displayTextFormat[displayTextLength-1].linkURL) + 1);
		}
		print_t_format(displayTextFormat[displayTextLength-1]);
		*numberOfSimplifiedTags+=1;
	}
	
	//now free
	for (int i = 0; i < displayTextLength; i++) {
		//do we have a linkURL and is it either different from the next one or are we the last one
		//this is neccesary so we don't double free the URL
		if (displayTextFormat[i].linkURL && ((i + 1 < displayTextLength && displayTextFormat[i+1].linkURL != displayTextFormat[i].linkURL) || (i+1 >= displayTextLength))) {
			free(displayTextFormat[i].linkURL);
			displayTextFormat[i].linkURL = NULL;
		}
	}
	
	free(displayTextFormat);
}
