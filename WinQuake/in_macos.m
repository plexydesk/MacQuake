// in_macos.m -- macOS input handling

#import <Cocoa/Cocoa.h>

#include "quakedef.h"

cvar_t m_filter = {"m_filter","0", true};
cvar_t _windowed_mouse = {"_windowed_mouse","1", true};

// Mouse state (from vid_macos.m)
extern float mouse_x, mouse_y;
extern float old_mouse_x, old_mouse_y;
extern int mouse_buttons;
extern int mouse_buttonstate;
extern int mouse_oldbuttonstate;
extern qboolean mouse_avail;

void IN_Init(void)
{
	Cvar_RegisterVariable(&m_filter);
	Cvar_RegisterVariable(&_windowed_mouse);

	if (COM_CheckParm("-nomouse"))
		return;

	mouse_x = mouse_y = 0.0;
	mouse_avail = true;
}

void IN_Shutdown(void)
{
	mouse_avail = false;
}

void IN_Commands(void)
{
	int i;

	if (!mouse_avail) return;

	for (i = 0; i < mouse_buttons; i++) {
		if ((mouse_buttonstate & (1<<i)) && !(mouse_oldbuttonstate & (1<<i)))
			Key_Event(K_MOUSE1 + i, true);

		if (!(mouse_buttonstate & (1<<i)) && (mouse_oldbuttonstate & (1<<i)))
			Key_Event(K_MOUSE1 + i, false);
	}
	mouse_oldbuttonstate = mouse_buttonstate;
}

void IN_Move(usercmd_t *cmd)
{
	if (!mouse_avail)
		return;

	if (m_filter.value) {
		mouse_x = (mouse_x + old_mouse_x) * 0.5;
		mouse_y = (mouse_y + old_mouse_y) * 0.5;
	}

	old_mouse_x = mouse_x;
	old_mouse_y = mouse_y;

	mouse_x *= sensitivity.value;
	mouse_y *= sensitivity.value;

	if ((in_strafe.state & 1) || (lookstrafe.value && (in_mlook.state & 1)))
		cmd->sidemove += m_side.value * mouse_x;
	else
		cl.viewangles[YAW] -= m_yaw.value * mouse_x;

	if (in_mlook.state & 1)
		V_StopPitchDrift();

	if ((in_mlook.state & 1) && !(in_strafe.state & 1)) {
		cl.viewangles[PITCH] += m_pitch.value * mouse_y;
		if (cl.viewangles[PITCH] > 80)
			cl.viewangles[PITCH] = 80;
		if (cl.viewangles[PITCH] < -70)
			cl.viewangles[PITCH] = -70;
	} else {
		if ((in_strafe.state & 1) && noclip_anglehack)
			cmd->upmove -= m_forward.value * mouse_y;
		else
			cmd->forwardmove -= m_forward.value * mouse_y;
	}

	mouse_x = mouse_y = 0.0;
}

void IN_ClearStates(void)
{
	mouse_x = mouse_y = 0.0;
	mouse_buttonstate = mouse_oldbuttonstate = 0;
}
