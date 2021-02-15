//
// Created by Allison Husain on 4/27/18.
//

// C program for array implementation of stack
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include "t_tag.h"
#include "Stack.h"

// A structure to represent a stack
struct Stack
{
	int top;
	unsigned capacity;
	struct t_tag* array;
};

// function to create a stack of given capacity. It initializes size of
// stack as 0
struct Stack* createStack(unsigned capacity)
{
	struct Stack* stack = (struct Stack*) malloc(sizeof(struct Stack));
	stack->capacity = capacity;
	stack->top = -1;
	stack->array = malloc(stack->capacity * sizeof(struct t_tag));
	return stack;
}

// Stack is full when top is equal to the last index
int isFull(struct Stack* stack)
{   return stack->top == stack->capacity - 1; }

// Stack is empty when top is equal to -1
int isEmpty(struct Stack* stack)
{   return stack->top == -1;  }

// Function to add an item to stack.  It increases top by 1
void push(struct Stack* stack, struct t_tag item)
{
	if (isFull(stack))
		return;
	stack->array[++stack->top] = item;
}

// Function to remove an item from stack.  It decreases top by 1
struct t_tag* pop(struct Stack* stack)
{
	if (isEmpty(stack))
		return NULL;
	return &stack->array[stack->top--];
}

void prepareForFree(struct Stack* stack) {
	free(stack->array);
}
