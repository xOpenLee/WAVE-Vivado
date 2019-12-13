/*
WAVE Frame Management

Copyright (C) 2019 by Shane W. Colton

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

// Include Headers -----------------------------------------------------------------------------------------------------

#include "frame.h"
#include "gpio.h"
#include "cmv12000.h"
#include "encoder.h"
#include "xtime_l.h"

// Private Pre-Processor Definitions -----------------------------------------------------------------------------------

#define FH_BUFFER_SIZE 1024

// Private Type Definitions --------------------------------------------------------------------------------------------

// 512B Frame Header Structure
typedef struct __attribute__((packed))
{
	// Start of Frame [32B]
	char delimeter[12];			// Frame delimiter, always "WAVE HELLO!\n"
	u32 nFrame;					// Frame number.
	u64 tFrameRead_us;			// Frame read (from sensor) timestamp in [us].
	u64 tFrameWrite_us;			// Frame write (to SSD) timestamp in [us].

	// Frame Information [16B]
	u16 wFrame;					// Width
	u16 hFrame;					// Height
	u8 reserved0[12];

	// Quantizer Settings [16B]
	u32 q_mult_HH1_HL1_LH1;		// Stage 1 quantizer settings.
	u32 q_mult_HH2_HL2_LH2;		// Stage 2 quantizer settings.
	u32 q_mult_HH3_HL3_LH3;		// Stage 3 quantizer settings.
	u32 q_mult_LL3;				// Stage 3 LPF quantizer setting.

	// Code Stream Address and Size [128B]
	u32 csAddr[16];				// Codestream addresses in [B].
	u32 csSize[16];				// Codestream sizes [B].

	// Padding [320B]
	u8 reserved1[320];
} FrameHeader_s;

// Private Function Prototypes -----------------------------------------------------------------------------------------

// Public Global Variables ---------------------------------------------------------------------------------------------

// Private Global Variables --------------------------------------------------------------------------------------------

// Frame header circular buffer in external DDR4 RAM.
FrameHeader_s * fhBuffer = (FrameHeader_s *) (0x18000000);
s32 nFramesIn = -1;
s32 nFramesOut = 0;

// Interrupt Handlers --------------------------------------------------------------------------------------------------

/*
Frame Overhead Time (FOT) Interrupt Service Routine
- Interrupt flag set by rising edge of FOT bit signal on the CMV12000 control channel.
- Interrupt flag cleared by software.
- Constructs frame headers in an external DDR4 buffer. DDR4 access does not compete with frame read-in if
  the ISR returns before the end of the FOT period, which lasts about 20-30us.
*/
void isrFOT(void * CallbackRef)
{
	XTime tFrameIn;
	u32 iFrameIn;

	XGpioPs_WritePin(&Gpio, T_EXP1_PIN, 1);		// Mark ISR entry.
	CMV_Input->FOT_int = 0x00000000;			// Clear the FOT interrupt flag.

	// Record codestream size for the just-captured frame (if one exists).
	if(nFramesIn >= 0)
	{
		iFrameIn = nFramesIn % FH_BUFFER_SIZE;
		for(int iCS = 0; iCS < 16; iCS++)
		{
			fhBuffer[iFrameIn].csSize[iCS] = Encoder->c_RAM_addr[iCS] - fhBuffer[iFrameIn].csAddr[iCS];
		}
	}

	// Check codestream RAM addresses for full threshold and roll over as necessary.
	// - Must be called AFTER recording codestream size for the just-captured frame.
	// - Must be called BEFORE recording codestream start addresses for the upcoming frame.
	// - Must return BEFORE the end of the FOT period and the start of frame read-in.
	encoderServiceRAMAddr();

	// Increment the input frame counter.
	nFramesIn++;
	iFrameIn = nFramesIn % FH_BUFFER_SIZE;

	// Wipe old data.
	memset(&fhBuffer[iFrameIn], 0, 512);

	// Time and index stamp the upcoming frame.
	XTime_GetTime(&tFrameIn);
	fhBuffer[iFrameIn].tFrameRead_us = tFrameIn / (COUNTS_PER_SECOND / 1000000);
	fhBuffer[iFrameIn].nFrame = nFramesIn;

	// Frame delimeter and info for the upcoming frame.
	memcpy(fhBuffer[iFrameIn].delimeter, "WAVE HELLO!\n",12);
	fhBuffer[iFrameIn].wFrame = 4096;
	fhBuffer[iFrameIn].hFrame = 3072;

	// Quantizer settings for the upcoming frame.
	// TO-DO: Right here is where the quantizer settings should be modified to hit bit rate target!
	fhBuffer[iFrameIn].q_mult_HH1_HL1_LH1 = Encoder->q_mult_HH1_HL1_LH1;
	fhBuffer[iFrameIn].q_mult_HH2_HL2_LH2 = Encoder->q_mult_HH2_HL2_LH2;
	fhBuffer[iFrameIn].q_mult_HH3_HL3_LH3 = Encoder->q_mult_HH3_HL3_LH3;
	fhBuffer[iFrameIn].q_mult_LL3 = (Encoder->control_q_mult_LL3) & 0xFFFF;

	// Codestream start addresses for the upcoming frame.
	for(int iCS = 0; iCS < 16; iCS++)
	{
		fhBuffer[iFrameIn].csAddr[iCS] = Encoder->c_RAM_addr[iCS];
	}

	XGpioPs_WritePin(&Gpio, T_EXP1_PIN, 0);		// Mark ISR exit.
}

// Public Function Definitions -----------------------------------------------------------------------------------------

// Private Function Definitions ----------------------------------------------------------------------------------------
