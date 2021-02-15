//
// Created by Allison Husain on 4/27/18.
//
#include "t_tag.h"
#ifndef HTMLTOATTR_STACK_H
#define HTMLTOATTR_STACK_H


struct Stack;
struct Stack* createStack(unsigned capacity);
int isFull(struct Stack* stack);
int isEmpty(struct Stack* stack);
void push(struct Stack* stack, struct t_tag);
struct t_tag* pop(struct Stack* stack);
void prepareForFree(struct Stack* stack);
#endif //HTMLTOATTR_STACK_H
