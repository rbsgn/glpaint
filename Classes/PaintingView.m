/*

File: PaintingView.m
Abstract: The class responsible for the finger painting. The class wraps the 
CAEAGLLayer from CoreAnimation into a convenient UIView subclass. The view 
content is basically an EAGL surface you render your OpenGL scene into.

Version: 1.7

Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple Inc.
("Apple") in consideration of your agreement to the following terms, and your
use, installation, modification or redistribution of this Apple software
constitutes acceptance of these terms.  If you do not agree with these terms,
please do not use, install, modify or redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and subject
to these terms, Apple grants you a personal, non-exclusive license, under
Apple's copyrights in this original Apple software (the "Apple Software"), to
use, reproduce, modify and redistribute the Apple Software, with or without
modifications, in source and/or binary forms; provided that if you redistribute
the Apple Software in its entirety and without modifications, you must retain
this notice and the following text and disclaimers in all such redistributions
of the Apple Software.
Neither the name, trademarks, service marks or logos of Apple Inc. may be used
to endorse or promote products derived from the Apple Software without specific
prior written permission from Apple.  Except as expressly stated in this notice,
no other rights or licenses, express or implied, are granted by Apple herein,
including but not limited to any patent rights that may be infringed by your
derivative works or by other works in which the Apple Software may be
incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR
DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY OF
CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY OR OTHERWISE, EVEN IF
APPLE HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Copyright (C) 2009 Apple Inc. All Rights Reserved.

*/

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>

#import "PaintingView.h"

//CLASS IMPLEMENTATIONS:

// A class extension to declare private methods
@interface PaintingView (private)

- (BOOL)createFramebuffer;
- (void)destroyFramebuffer;

@end

@implementation PaintingView

@synthesize  location;
@synthesize  previousLocation;

// Implement this to override the default layer class (which is [CALayer class]).
// We do this so that our view will be backed by a layer that is capable of OpenGL ES rendering.
+ (Class) layerClass
{
	return [CAEAGLLayer class];
}

// The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
- (id)initWithCoder:(NSCoder*)coder {
	
	NSMutableArray*	recordedPaths;
	CGImageRef		brushImage;
	CGContextRef	brushContext;
	GLubyte			*brushData;
	size_t			width, height;
    
    if ((self = [super initWithCoder:coder])) {
		CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
		
		eaglLayer.opaque = YES;
		// In this application, we want to retain the EAGLDrawable contents after a call to presentRenderbuffer.
		eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
										[NSNumber numberWithBool:YES], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
		
		context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
		
		if (!context || ![EAGLContext setCurrentContext:context]) {
			[self release];
			return nil;
		}
		
		// Create a texture from an image
		// First create a UIImage object from the data in a image file, and then extract the Core Graphics image
		brushImage = [UIImage imageNamed:@"Particle.png"].CGImage;
		
		// Get the width and height of the image
		width = CGImageGetWidth(brushImage);
		height = CGImageGetHeight(brushImage);
		
		// Texture dimensions must be a power of 2. If you write an application that allows users to supply an image,
		// you'll want to add code that checks the dimensions and takes appropriate action if they are not a power of 2.
		
		// Make sure the image exists
		if(brushImage) {
			// Allocate  memory needed for the bitmap context
			brushData = (GLubyte *) calloc(width * height * 4, sizeof(GLubyte));
			// Use  the bitmatp creation function provided by the Core Graphics framework. 
			brushContext = CGBitmapContextCreate(brushData, width, width, 8, width * 4, CGImageGetColorSpace(brushImage), kCGImageAlphaPremultipliedLast);
			// After you create the context, you can draw the  image to the context.
			CGContextDrawImage(brushContext, CGRectMake(0.0, 0.0, (CGFloat)width, (CGFloat)height), brushImage);
			// You don't need the context at this point, so you need to release it to avoid memory leaks.
			CGContextRelease(brushContext);
			// Use OpenGL ES to generate a name for the texture.
			glGenTextures(1, &brushTexture);
			// Bind the texture name. 
			glBindTexture(GL_TEXTURE_2D, brushTexture);
			// Set the texture parameters to use a minifying filter and a linear filer (weighted average)
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
			// Specify a 2D texture image, providing the a pointer to the image data in memory
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, brushData);
			// Release  the image data; it's no longer needed
            free(brushData);
			
			// Enable use of the texture
			glEnable(GL_TEXTURE_2D);
			// Set a blending function to use
			glBlendFunc(GL_SRC_ALPHA, GL_ONE);
			// Enable blending
			glEnable(GL_BLEND);
		}
		
		//Set up OpenGL states
		glMatrixMode(GL_PROJECTION);
		CGRect frame = self.bounds;
		glOrthof(0, frame.size.width, 0, frame.size.height, -1, 1);
		glViewport(0, 0, frame.size.width, frame.size.height);
		glMatrixMode(GL_MODELVIEW);
		
		glDisable(GL_DITHER);
		glEnable(GL_TEXTURE_2D);
		glEnableClientState(GL_VERTEX_ARRAY);
	    glEnable(GL_BLEND);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE);
		glEnable(GL_POINT_SPRITE_OES);
		glTexEnvf(GL_POINT_SPRITE_OES, GL_COORD_REPLACE_OES, GL_TRUE);
		glPointSize(width / kBrushScale);
		
		//Make sure to start with a cleared buffer
		needsErase = YES;
		
		//Playback recorded path, which is "Shake Me"
		recordedPaths = [NSMutableArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Recording" ofType:@"data"]];
		if([recordedPaths count])
			[self performSelector:@selector(playback:) withObject:recordedPaths afterDelay:0.2];
	}
	
	return self;
}

// If our view is resized, we'll be asked to layout subviews.
// This is the perfect opportunity to also update the framebuffer so that it is
// the same size as our display area.
-(void)layoutSubviews
{
	[EAGLContext setCurrentContext:context];
	[self destroyFramebuffer];
	[self createFramebuffer];
	
	// Clear the framebuffer the first time it is allocated
	if (needsErase) {
		[self erase];
		needsErase = NO;
	}
}

- (BOOL)createFramebuffer
{
	// Generate IDs for a framebuffer object and a color renderbuffer
	glGenFramebuffersOES(1, &viewFramebuffer);
	glGenRenderbuffersOES(1, &viewRenderbuffer);
	
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
	// This call associates the storage for the current render buffer with the EAGLDrawable (our CAEAGLLayer)
	// allowing us to draw into a buffer that will later be rendered to screen wherever the layer is (which corresponds with our view).
	[context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(id<EAGLDrawable>)self.layer];
	glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, viewRenderbuffer);
	
	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
	
	// For this sample, we also need a depth buffer, so we'll create and attach one via another renderbuffer.
	glGenRenderbuffersOES(1, &depthRenderbuffer);
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, depthRenderbuffer);
	glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, backingWidth, backingHeight);
	glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, depthRenderbuffer);
	
	if(glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES)
	{
		NSLog(@"failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
		return NO;
	}
	
	return YES;
}

// Clean up any buffers we have allocated.
- (void)destroyFramebuffer
{
	glDeleteFramebuffersOES(1, &viewFramebuffer);
	viewFramebuffer = 0;
	glDeleteRenderbuffersOES(1, &viewRenderbuffer);
	viewRenderbuffer = 0;
	
	if(depthRenderbuffer)
	{
		glDeleteRenderbuffersOES(1, &depthRenderbuffer);
		depthRenderbuffer = 0;
	}
}

// Releases resources when they are not longer needed.
- (void) dealloc
{
	if (brushTexture)
	{
		glDeleteTextures(1, &brushTexture);
		brushTexture = 0;
	}
	
	if([EAGLContext currentContext] == context)
	{
		[EAGLContext setCurrentContext:nil];
	}
	
	[context release];
	[super dealloc];
}

// Erases the screen
- (void) erase
{
	[EAGLContext setCurrentContext:context];
	
	//Clear the buffer
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
	glClear(GL_COLOR_BUFFER_BIT);
	glClearColor(0.0, 0.0, 0.0, 1.0);
	
	//Display the buffer
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
	[context presentRenderbuffer:GL_RENDERBUFFER_OES];
}

// Drawings a line onscreen based on where the user touches
- (void) renderLineFromPoint:(CGPoint)start toPoint:(CGPoint)end
{
	static GLfloat*		vertexBuffer = NULL;
	static NSUInteger	vertexMax = 64;
	NSUInteger			vertexCount = 0,
						count,
						i;
	
	[EAGLContext setCurrentContext:context];
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
	
	//Allocate vertex array buffer
	if(vertexBuffer == NULL)
		vertexBuffer = malloc(vertexMax * 2 * sizeof(GLfloat));
	
	//Add points to the buffer so there are drawing points every X pixels
	count = MAX(ceilf(sqrtf((end.x - start.x) * (end.x - start.x) + (end.y - start.y) * (end.y - start.y)) / kBrushPixelStep), 1);
	for(i = 0; i < count; ++i) {
		if(vertexCount == vertexMax) {
			vertexMax = 2 * vertexMax;
			vertexBuffer = realloc(vertexBuffer, vertexMax * 2 * sizeof(GLfloat));
		}
		
		vertexBuffer[2 * vertexCount + 0] = start.x + (end.x - start.x) * ((GLfloat)i / (GLfloat)count);
		vertexBuffer[2 * vertexCount + 1] = start.y + (end.y - start.y) * ((GLfloat)i / (GLfloat)count);
		vertexCount += 1;
	}
	
	//Render the vertex array
	glVertexPointer(2, GL_FLOAT, 0, vertexBuffer);
	glDrawArrays(GL_POINTS, 0, vertexCount);
	
	//Display the buffer
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
	[context presentRenderbuffer:GL_RENDERBUFFER_OES];
}

// Reads previously recorded points and draws them onscreen. This is the Shake Me message that appears when the application launches.
- (void) playback:(NSMutableArray*)recordedPaths
{
	NSData*				data = [recordedPaths objectAtIndex:0];
	CGPoint*			point = (CGPoint*)[data bytes];
	NSUInteger			count = [data length] / sizeof(CGPoint),
						i;
	
	//Render the current path
	for(i = 0; i < count - 1; ++i, ++point)
		[self renderLineFromPoint:*point toPoint:*(point + 1)];
	
	//Render the next path after a short delay 
	[recordedPaths removeObjectAtIndex:0];
	if([recordedPaths count])
		[self performSelector:@selector(playback:) withObject:recordedPaths afterDelay:0.01];
}


// Handles the start of a touch
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	CGRect				bounds = [self bounds];
    UITouch*	touch = [[event touchesForView:self] anyObject];
	firstTouch = YES;
	//Convert touch point from UIView referential to OpenGL one (upside-down flip)
	location = [touch locationInView:self];
	location.y = bounds.size.height - location.y;
}

// Handles the continuation of a touch.
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{  
   	  
	CGRect				bounds = [self bounds];
	UITouch*			touch = [[event touchesForView:self] anyObject];
		
	//Convert touch point from UIView referential to OpenGL one (upside-down flip)
	if (firstTouch) {
		firstTouch = NO;
		previousLocation = [touch previousLocationInView:self];
		previousLocation.y = bounds.size.height - previousLocation.y;
	} else {
		location = [touch locationInView:self];
	    location.y = bounds.size.height - location.y;
		previousLocation = [touch previousLocationInView:self];
		previousLocation.y = bounds.size.height - previousLocation.y;
	}
		
	// Render the stroke
	[self renderLineFromPoint:previousLocation toPoint:location];
}

// Handles the end of a touch event when the touch is a tap.
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
	CGRect				bounds = [self bounds];
    UITouch*	touch = [[event touchesForView:self] anyObject];
	if (firstTouch) {
		firstTouch = NO;
		previousLocation = [touch previousLocationInView:self];
		previousLocation.y = bounds.size.height - previousLocation.y;
		[self renderLineFromPoint:previousLocation toPoint:location];
	}
}

// Handles the end of a touch event.
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
	// If appropriate, add code necessary to save the state of the application.
	// This application is not saving state.
}

@end
