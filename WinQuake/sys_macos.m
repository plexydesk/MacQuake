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
// sys_macos.c -- macOS system interface

#include <unistd.h>
#include <signal.h>
#include <stdlib.h>
#include <limits.h>
#include <sys/time.h>
#include <sys/types.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <sys/stat.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <sys/mman.h>
#include <mach/mach_time.h>

#include "quakedef.h"

qboolean isDedicated = false;
int nostdout = 0;
char *basedir = ".";
char *cachedir = "/tmp";
cvar_t sys_linerefresh = {"sys_linerefresh","0"};

static double timebase = 0.0;
static mach_timebase_info_data_t timebase_info;

// ========================================================================
// General routines
// ========================================================================

void Sys_DebugNumber(int y, int val)
{
}

void Sys_Printf(char *fmt, ...)
{
	va_list argptr;
	char text[1024];
	unsigned char *p;

	va_start(argptr, fmt);
	vsprintf(text, fmt, argptr);
	va_end(argptr);

	if (strlen(text) > sizeof(text))
		Sys_Error("memory overwrite in Sys_Printf");

	if (nostdout)
		return;

	for (p = (unsigned char *)text; *p; p++) {
		*p &= 0x7f;
		if ((*p > 128 || *p < 32) && *p != 10 && *p != 13 && *p != 9)
			printf("[%02x]", *p);
		else
			putc(*p, stdout);
	}
	fflush(stdout);
}

void Sys_Quit(void)
{
	Host_Shutdown();
	fflush(stdout);
	exit(0);
}

void Sys_Init(void)
{
}

void Sys_Error(char *error, ...)
{
	va_list argptr;
	char string[1024];

	va_start(argptr, error);
	vsprintf(string, error, argptr);
	va_end(argptr);

	fprintf(stderr, "Error: %s\n", string);

	Host_Shutdown();
	exit(1);
}

void Sys_Warn(char *warning, ...)
{
	va_list argptr;
	char string[1024];

	va_start(argptr, warning);
	vsprintf(string, warning, argptr);
	va_end(argptr);

	fprintf(stderr, "Warning: %s", string);
}

// ========================================================================
// File I/O
// ========================================================================

int Sys_FileTime(char *path)
{
	struct stat buf;

	if (stat(path, &buf) == -1)
		return -1;

	return buf.st_mtime;
}

void Sys_mkdir(char *path)
{
	mkdir(path, 0777);
}

int Sys_FileOpenRead(char *path, int *handle)
{
	int h;
	struct stat fileinfo;

	h = open(path, O_RDONLY, 0666);
	*handle = h;
	if (h == -1)
		return -1;

	if (fstat(h, &fileinfo) == -1)
		Sys_Error("Error fstating %s", path);

	return fileinfo.st_size;
}

int Sys_FileOpenWrite(char *path)
{
	int handle;

	umask(0);
	handle = open(path, O_RDWR | O_CREAT | O_TRUNC, 0666);

	if (handle == -1)
		Sys_Error("Error opening %s: %s", path, strerror(errno));

	return handle;
}

int Sys_FileWrite(int handle, void *src, int count)
{
	return write(handle, src, count);
}

void Sys_FileClose(int handle)
{
	close(handle);
}

void Sys_FileSeek(int handle, int position)
{
	lseek(handle, position, SEEK_SET);
}

int Sys_FileRead(int handle, void *dest, int count)
{
	return read(handle, dest, count);
}

void Sys_DebugLog(char *file, char *fmt, ...)
{
	va_list argptr;
	static char data[1024];
	int fd;

	va_start(argptr, fmt);
	vsprintf(data, fmt, argptr);
	va_end(argptr);

	fd = open(file, O_WRONLY | O_CREAT | O_APPEND, 0666);
	write(fd, data, strlen(data));
	close(fd);
}

void Sys_EditFile(char *filename)
{
	// Not supported on macOS
}

// ========================================================================
// Timing
// ========================================================================

double Sys_FloatTime(void)
{
	uint64_t now;
	
	if (timebase == 0.0) {
		mach_timebase_info(&timebase_info);
		timebase = (double)mach_absolute_time();
	}

	now = mach_absolute_time();
	return ((double)(now - (uint64_t)timebase) * (double)timebase_info.numer / (double)timebase_info.denom) / 1000000000.0;
}

// ========================================================================
// Console Input
// ========================================================================

char *Sys_ConsoleInput(void)
{
	static char text[256];
	int len;
	fd_set fdset;
	struct timeval timeout;

	if (cls.state == ca_dedicated) {
		FD_ZERO(&fdset);
		FD_SET(0, &fdset);
		timeout.tv_sec = 0;
		timeout.tv_usec = 0;
		if (select(1, &fdset, NULL, NULL, &timeout) == -1 || !FD_ISSET(0, &fdset))
			return NULL;

		len = read(0, text, sizeof(text));
		if (len < 1)
			return NULL;
		text[len - 1] = 0;

		return text;
	}
	return NULL;
}

void Sys_Sleep(void)
{
	usleep(1000);
}

void Sys_SendKeyEvents(void)
{
}

void Sys_LineRefresh(void)
{
}

#if !id386
void Sys_HighFPPrecision(void)
{
}

void Sys_LowFPPrecision(void)
{
}
#endif

// ========================================================================
// Memory protection
// ========================================================================

void Sys_MakeCodeWriteable(unsigned long startaddr, unsigned long length)
{
	int r;
	unsigned long addr;
	int psize = getpagesize();

	addr = (startaddr & ~(psize - 1)) - psize;

	r = mprotect((char *)addr, length + startaddr - addr + psize,
			PROT_READ | PROT_WRITE | PROT_EXEC);

	if (r < 0)
		Sys_Error("Protection change failed\n");
}

// ========================================================================
// Main
// ========================================================================

extern void VID_InitCocoa(void);
extern void VID_ShutdownCocoa(void);
extern void VID_PumpEvents(void);
extern void Metal_Init(void);
extern void Metal_Shutdown(void);

int main(int c, char **v)
{
	double time, oldtime, newtime;
	quakeparms_t parms;
	extern int vcrFile;
	extern int recording;
	int j;

	signal(SIGFPE, SIG_IGN);

	memset(&parms, 0, sizeof(parms));

	COM_InitArgv(c, v);
	parms.argc = com_argc;
	parms.argv = com_argv;

	parms.memsize = 8 * 1024 * 1024;

	j = COM_CheckParm("-mem");
	if (j)
		parms.memsize = (int)(Q_atof(com_argv[j + 1]) * 1024 * 1024);
	parms.membase = malloc(parms.memsize);

	parms.basedir = basedir;

	Host_Init(&parms);
	Sys_Init();

	if (COM_CheckParm("-nostdout"))
		nostdout = 1;
	else {
		printf("macOS Quake -- Version %0.3f\n", VERSION);
	}

	oldtime = Sys_FloatTime() - 0.1;
	while (1) {
		@autoreleasepool {
			// Pump Cocoa events
			VID_PumpEvents();

			newtime = Sys_FloatTime();
			time = newtime - oldtime;

			if (cls.state == ca_dedicated) {
				if (time < sys_ticrate.value && (vcrFile == -1 || recording)) {
					usleep(1000);
					continue;
				}
				time = sys_ticrate.value;
			}

			if (time > sys_ticrate.value * 2)
				oldtime = newtime;
			else
				oldtime += time;

			Host_Frame(time);

			if (sys_linerefresh.value)
				Sys_LineRefresh();
		}
	}

	return 0;
}
