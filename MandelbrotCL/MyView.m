#import "MyView.h"
#import <stdio.h>

#define DEBUG 1

#if DEBUG == 1
	#define ERR_(x) printf("\n %s \n\t %s '%s' %d\n", #x, __FUNCTION__, __FILE__, __LINE__);
	#define HERE    printf("\n<%s: %p> - %s\n", [[self className] UTF8String], (void*)self, sel_getName(_cmd));
	#define _o(o)   printf("%s: %s\n", #o, [[(o) description] UTF8String]);
#else
	#define ERR_(x) {}
	#define HERE    {}
	#define _o(o)   {}
#endif


@implementation MyView

- (BOOL)setupDeviceWithSourceBytes:(const char*)sourceBytes
						kernelName:(const char*)kernelName
{
	int err;
	
	cl_device_id deviceList[10];
	unsigned deviceCount;
	err = clGetDeviceIDs(NULL, CL_DEVICE_TYPE_ALL, 10, deviceList, &deviceCount);
	if ( err != CL_SUCCESS )
	{
		ERR_(get device IDs)
		return NO;
	}
	
	printf("\n");
	printf("%d devices found\n", deviceCount);
	for ( int i = 0; i < deviceCount; i++ )
	{
		char deviceName[1024] = { 0 };
		size_t len;
        clGetDeviceInfo(deviceList[i], CL_DEVICE_NAME, sizeof(deviceName), deviceName, &len);
		printf("[%d] %s\n", i, deviceName);
	}
	printf("\n");
	
	_deviceID = deviceList[0];
	
	_context = clCreateContext(0, 1, &_deviceID, NULL, NULL, &err);
	if ( !_context )
	{
		ERR_(create context)
		return NO;
	}
	
	_queue = clCreateCommandQueue(_context, _deviceID, 0, &err);
	if ( !_queue )
	{
		ERR_(create command queue)
		return NO;
	}
	
	_program = clCreateProgramWithSource(_context, 1, &sourceBytes, NULL, &err);
	if ( err != CL_SUCCESS )
	{
		ERR_(create program with source)
		return NO;
	}
	
	// compile
	err = clBuildProgram(_program, 0, NULL, NULL, NULL, NULL);
	if ( err != CL_SUCCESS )
	{
		size_t len;
		char log[2048];
		
		printf("Error: Failed to build program executable\n");
		clGetProgramBuildInfo(_program, _deviceID, CL_PROGRAM_BUILD_LOG, sizeof(log), log, &len);
		printf("%s\n", log);
		return NO;
	}
	
	_kernel = clCreateKernel(_program, kernelName, &err);
	if ( !_kernel || err != CL_SUCCESS )
	{
		ERR_(create kernel)
		return NO;
	}
	
	size_t len = _viewW * _viewH;
	_output = clCreateBuffer(_context, CL_MEM_WRITE_ONLY, len, NULL, NULL);
	if ( !_output )
	{
		ERR_(create buffer)
		return NO;
	}
	
	return YES;
}

- (void)closeDevice
{
HERE
	clReleaseContext(_context);
	clReleaseCommandQueue(_queue);
	clReleaseProgram(_program);
	clReleaseKernel(_kernel);
	clReleaseMemObject(_output);
}

- (float)unit
{
	return 1.0 / 200 / powf(2.0f, _scaleIndex);
}

- (void)showStatus:(double)elapseTime
{
	NSString* s = [NSString stringWithFormat:
		@"FPS: %.1f (%.1f ms)"
		@"  center:(%.3f,%.3f)",
		1.0 / elapseTime, 1000 * elapseTime,
		_centerX, _centerY];
	[_label setStringValue:s];
}

- (void)execute
{
	double t0 = [NSDate timeIntervalSinceReferenceDate];
	
	int err;
	
	float unit = [self unit];
	
	err = 0;
	err |= clSetKernelArg(_kernel, 0, sizeof(cl_mem), &_output);
	err |= clSetKernelArg(_kernel, 1, sizeof(_viewW), &_viewW);
	err |= clSetKernelArg(_kernel, 2, sizeof(_viewH), &_viewH);
	err |= clSetKernelArg(_kernel, 3, sizeof(_centerX), &_centerX);
	err |= clSetKernelArg(_kernel, 4, sizeof(_centerY), &_centerY);
	err |= clSetKernelArg(_kernel, 5, sizeof(unit), &unit);
	if ( err != CL_SUCCESS )
	{
		ERR_(set kernel arg)
		return;
	}
	
	size_t local;
	err = clGetKernelWorkGroupInfo(_kernel, _deviceID, CL_KERNEL_WORK_GROUP_SIZE, sizeof(local), &local, NULL);
	if ( err != CL_SUCCESS )
	{
		ERR_(get kernel work group info)
		return;
	}
	
	size_t global = _viewW * _viewH;
	err = clEnqueueNDRangeKernel(_queue, _kernel, 1, NULL, &global, &local, 0, NULL, NULL);
	if ( err )
	{
		ERR_(enqueue ND range kernel)
		return;
	}
	
	clFinish(_queue);
	
	size_t len = _viewW * _viewH;
	void* pointer = [_bitmap bitmapData];
	err = clEnqueueReadBuffer(_queue, _output, CL_TRUE, 0, len, pointer, 0, NULL, NULL);
	if ( err != CL_SUCCESS )
	{
		ERR_(enqueue read buffer)
		return;
	}
	
	double t1 = [NSDate timeIntervalSinceReferenceDate];
	[self showStatus:(t1 - t0)];
	
	[self setNeedsDisplay:YES];
}

- (NSPoint)pointOfEvent:(NSEvent*)event
{
	NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
	if ( ![self isFlipped] ) p.y -= 1;
	return p;
}

- (void)mouseDown:(NSEvent*)event
{
	float unit = [self unit];
	NSPoint p0 = [self pointOfEvent:event];
	unsigned mask = 0;
	mask |= NSLeftMouseDownMask;
	mask |= NSLeftMouseDraggedMask;
	mask |= NSLeftMouseUpMask;
	while ( 1 )
	{
		event = [[self window] nextEventMatchingMask:mask];
		if ( [event type] == NSLeftMouseUp ) break;
		NSPoint p1 = [self pointOfEvent:event];
		float deltaX = p1.x - p0.x;
		float deltaY = p1.y - p0.y;
		p0 = p1;
		deltaX *= unit;
		deltaY *= unit;
		_centerX -= deltaX;
		_centerY -= deltaY;
		[self execute];
	}
}

- (void)scrollWheel:(NSEvent*)event
{
	_scaleIndex += [event deltaY] > 0 ? +0.2 : -0.2;
	[self execute];
}

- (id)initWithFrame:(NSRect)frameRect
{
HERE
	self = [super initWithFrame:frameRect];
	if ( !self ) return nil;
	
	NSSize size = [self frame].size;
	_viewW = (int)size.width;
	_viewH = (int)size.height;
	_centerX = -0.775;
	_centerY = +0.124;
	_scaleIndex = 0;
	
	_bitmap = [[NSBitmapImageRep alloc]
		initWithBitmapDataPlanes:0
					  pixelsWide:_viewW
					  pixelsHigh:_viewH
				   bitsPerSample:8
				 samplesPerPixel:1
						hasAlpha:NO
						isPlanar:NO
				  colorSpaceName:NSDeviceWhiteColorSpace
					 bytesPerRow:1 * _viewW
					bitsPerPixel:1 * 8];
	
	return self;
}

- (void)applicationDidFinishLaunching:(id)notif
{
HERE
	NSString* fileName = @"Mandelbrot.cl";
	NSString* sourcePath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:fileName];
	NSError* error = nil;
	NSString* sourceString = [NSString stringWithContentsOfFile:sourcePath
													   encoding:NSUTF8StringEncoding
														  error:&error];
	if ( error )
	{
		_o(error)
		return;
	}
	const char* sourceBytes = [sourceString UTF8String];
	[self setupDeviceWithSourceBytes:sourceBytes
						  kernelName:"Mandelbrot"];
	[self execute];
}

- (void)applicationWillTerminate:(id)notif
{
HERE
	[self closeDevice];
}

- (void)drawRect:(NSRect)updateRect
{
	[_bitmap draw];
}

@end
