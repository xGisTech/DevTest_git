#import <Cocoa/Cocoa.h>
#import <OpenCL/opencl.h>

@interface MyView : NSView
{
	IBOutlet id _label;
	
	// OpenCL
	cl_device_id     _deviceID;
	cl_context       _context;
	cl_command_queue _queue;
	cl_program       _program;
	cl_kernel        _kernel;
	cl_mem           _output;
	
	// Mandelbrot calculation
	int   _viewW;
	int   _viewH;
	float _centerX;
	float _centerY;
	float _scaleIndex;
	
	// display
	NSBitmapImageRep* _bitmap;
}
@end
