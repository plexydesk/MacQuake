/*
Copyright (C) 1996-1997 Id Software, Inc.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  

See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

*/
// snd_macos.c -- macOS Core Audio sound driver

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AudioToolbox.h>

#include "quakedef.h"

static int snd_inited = 0;
static AudioUnit outputUnit;
static int playpos = 0;

static OSStatus RenderCallback(void *inRefCon,
								AudioUnitRenderActionFlags *ioActionFlags,
								const AudioTimeStamp *inTimeStamp,
								UInt32 inBusNumber,
								UInt32 inNumberFrames,
								AudioBufferList *ioData)
{
	int i;
	int out_mask;
	unsigned char *buffer;

	if (!snd_inited || !shm || !shm->buffer)
		return noErr;

	buffer = shm->buffer;
	out_mask = shm->samples - 1;

	if (ioData->mNumberBuffers < 1)
		return noErr;

	if (shm->samplebits == 16 && shm->channels == 2) {
		// Interleaved stereo output
		short *out = (short *)ioData->mBuffers[0].mData;
		short *p = (short *)buffer;
		for (i = 0; i < (int)inNumberFrames; i++) {
			int idx = (playpos * 2) & out_mask;
			out[i * 2] = p[idx];
			out[i * 2 + 1] = p[idx + 1];
			playpos++;
		}
	} else if (shm->samplebits == 16 && shm->channels == 1) {
		short *out = (short *)ioData->mBuffers[0].mData;
		short *p = (short *)buffer;
		for (i = 0; i < (int)inNumberFrames; i++) {
			out[i] = p[playpos & out_mask];
			playpos++;
		}
	} else if (shm->samplebits == 8 && shm->channels == 2) {
		unsigned char *out = (unsigned char *)ioData->mBuffers[0].mData;
		unsigned char *p = buffer;
		for (i = 0; i < (int)inNumberFrames; i++) {
			int idx = (playpos * 2) & out_mask;
			out[i * 2] = p[idx];
			out[i * 2 + 1] = p[idx + 1];
			playpos++;
		}
	} else {
		unsigned char *out = (unsigned char *)ioData->mBuffers[0].mData;
		unsigned char *p = buffer;
		for (i = 0; i < (int)inNumberFrames; i++) {
			out[i] = p[playpos & out_mask];
			playpos++;
		}
	}

	return noErr;
}

qboolean SNDDMA_Init(void)
{
	AudioComponentDescription desc;
	AudioComponent comp;
	OSStatus err;
	AudioStreamBasicDescription fmt;
	int i;
	char *s;

	snd_inited = 0;
	playpos = 0;

	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_DefaultOutput;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;
	desc.componentFlags = 0;
	desc.componentFlagsMask = 0;

	comp = AudioComponentFindNext(NULL, &desc);
	if (!comp) {
		Con_Printf("AudioComponentFindNext failed\n");
		return 0;
	}

	err = AudioComponentInstanceNew(comp, &outputUnit);
	if (err != noErr) {
		Con_Printf("AudioComponentInstanceNew failed: %d\n", (int)err);
		return 0;
	}

	AURenderCallbackStruct callbackStruct;
	callbackStruct.inputProc = RenderCallback;
	callbackStruct.inputProcRefCon = NULL;

	err = AudioUnitSetProperty(outputUnit,
							   kAudioUnitProperty_SetRenderCallback,
							   kAudioUnitScope_Input,
							   0,
							   &callbackStruct,
							   sizeof(callbackStruct));
	if (err != noErr) {
		Con_Printf("AudioUnitSetProperty (callback) failed: %d\n", (int)err);
		AudioComponentInstanceDispose(outputUnit);
		return 0;
	}

	shm = &sn;

	shm->channels = 2;
	s = getenv("QUAKE_SOUND_CHANNELS");
	if (s)
		shm->channels = atoi(s);
	else if ((i = COM_CheckParm("-sndmono")) != 0)
		shm->channels = 1;
	else if ((i = COM_CheckParm("-sndstereo")) != 0)
		shm->channels = 2;

	shm->samplebits = 16;
	s = getenv("QUAKE_SOUND_SAMPLEBITS");
	if (s)
		shm->samplebits = atoi(s);
	else if ((i = COM_CheckParm("-sndbits")) != 0)
		shm->samplebits = atoi(com_argv[i + 1]);

	shm->speed = 22050;
	s = getenv("QUAKE_SOUND_SPEED");
	if (s)
		shm->speed = atoi(s);
	else if ((i = COM_CheckParm("-sndspeed")) != 0)
		shm->speed = atoi(com_argv[i + 1]);

	// Set up stream format
	memset(&fmt, 0, sizeof(fmt));
	fmt.mSampleRate = shm->speed;
	fmt.mFormatID = kAudioFormatLinearPCM;
	fmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	fmt.mChannelsPerFrame = shm->channels;
	fmt.mBitsPerChannel = shm->samplebits;
	fmt.mBytesPerFrame = (shm->samplebits / 8) * shm->channels;
	fmt.mFramesPerPacket = 1;
	fmt.mBytesPerPacket = fmt.mBytesPerFrame;

	err = AudioUnitSetProperty(outputUnit,
							   kAudioUnitProperty_StreamFormat,
							   kAudioUnitScope_Input,
							   0,
							   &fmt,
							   sizeof(fmt));
	if (err != noErr) {
		Con_Printf("AudioUnitSetProperty (format) failed: %d\n", (int)err);
		AudioComponentInstanceDispose(outputUnit);
		return 0;
	}

	err = AudioUnitInitialize(outputUnit);
	if (err != noErr) {
		Con_Printf("AudioUnitInitialize failed: %d\n", (int)err);
		AudioComponentInstanceDispose(outputUnit);
		return 0;
	}

	err = AudioOutputUnitStart(outputUnit);
	if (err != noErr) {
		Con_Printf("AudioOutputUnitStart failed: %d\n", (int)err);
		AudioUnitUninitialize(outputUnit);
		AudioComponentInstanceDispose(outputUnit);
		return 0;
	}

	shm->samples = 32768;  // must be power of 2
	shm->submission_chunk = 1;
	shm->samplepos = 0;

	int buffer_size = shm->samples * (shm->samplebits / 8);
	shm->buffer = (unsigned char *)malloc(buffer_size);
	if (!shm->buffer) {
		Con_Printf("Failed to allocate sound buffer\n");
		AudioOutputUnitStop(outputUnit);
		AudioUnitUninitialize(outputUnit);
		AudioComponentInstanceDispose(outputUnit);
		return 0;
	}
	memset((void *)shm->buffer, 0, buffer_size);

	snd_inited = 1;
	return 1;
}

int SNDDMA_GetDMAPos(void)
{
	if (!snd_inited)
		return 0;

	shm->samplepos = playpos & (shm->samples - 1);
	return shm->samplepos;
}

void SNDDMA_Shutdown(void)
{
	if (snd_inited) {
		AudioOutputUnitStop(outputUnit);
		AudioUnitUninitialize(outputUnit);
		AudioComponentInstanceDispose(outputUnit);
		if (shm && shm->buffer) {
			free((void *)shm->buffer);
			shm->buffer = NULL;
		}
		snd_inited = 0;
	}
}

void SNDDMA_Submit(void)
{
}
