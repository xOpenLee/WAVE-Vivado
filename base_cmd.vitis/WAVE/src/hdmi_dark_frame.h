/*
HDMI Dark Frame Subtraction Include

Copyright (C) 2020 by Shane W. Colton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

#ifndef __HDMI_DARK_FRAME_INCLUDE__
#define __HDMI_DARK_FRAME_INCLUDE__

// Include Headers -----------------------------------------------------------------------------------------------------

// Public Pre-Processor Definitions ------------------------------------------------------------------------------------

#define DARK_FRAME_W 4096
#define DARK_FRAME_H 3072

// Public Type Definitions ---------------------------------------------------------------------------------------------

typedef struct __attribute__((packed))
{
	s16 G1;
	s16 R1;
	s16 B1;
	s16 G2;
} DarkFrameColor_s; // [64B]

typedef struct __attribute__((packed))
{
	DarkFrameColor_s row[DARK_FRAME_H];
	DarkFrameColor_s col[DARK_FRAME_W];
	u16 offsetBot;
	u16 offsetTop;
	s8 temp;
	u8 reserved[8187];
} DarkFrame_s; // [64KiB]

// Public Function Prototypes ------------------------------------------------------------------------------------------

// Load a dark frame from flash into the active dark frame in RAM.
void hdmiDarkFrameCreate(u16 wFrame, float temp);

// Zero the dark frame in RAM.
void hdmiDarkFrameZero(void);

// Build a test dark frame in RAM that darkens the top half and left half of the image.
void hdmiDarkFrameTest(void);

// Adapt the dark frame in RAM based on the last captured frame.
// void hdmiDarkFrameAdapt(s32 frame, u32 nSamples, s16 targetBlack);

// Apply the active dark frame in RAM to the HDMI peripheral dark frame URAMs.
void hdmiDarkFrameApply(u16 wFrame, u16 hFrame);

// Externed Public Global Variables ------------------------------------------------------------------------------------

extern DarkFrame_s * dfCold;
extern DarkFrame_s * dfWarm;
extern DarkFrame_s dfActive;

#endif
