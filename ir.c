/***************************************************************************************************
                                    ExploreEmbedded Copyright Notice 
****************************************************************************************************
 * File:   necIrRemoteExample1.c (Modified)
 * Version: 16.0
 * Author: ExploreEmbedded (Modified)
 * Website: http://www.exploreembedded.com/wiki
 * Description: Modified program to control P2 based on NEC IR Remote buttons 2,4,6,8 using 8051 controller.
This code has been developed and tested on ExploreEmbedded boards.  
We strongly believe that the library works on any of development boards for respective controllers. 
Check this link http://www.exploreembedded.com/wiki for awesome tutorials on 8051,PIC,AVR,ARM,Robotics,RTOS,IOT.
ExploreEmbedded invests substantial time and effort developing open source HW and SW tools, to support consider 
buying the ExploreEmbedded boards.
 
The ExploreEmbedded libraries and examples are licensed under the terms of the new-bsd license(two-clause bsd license).
See also: http://www.opensource.org/licenses/bsd-license.php
**************************************************************************************************/

/*************************
  NEC IR Remote Codes Used:
  0xFF18E7: 2         
  0xFF10EF: 4         
  0xFF5AA5: 6         
  0xFF4AB5: 8         
**************************/
 
#include <reg51.h>

typedef unsigned char uint8_t;

/* ---------- Globals ---------- */
uint8_t  bitPattern[4] = {0};   /* 32 bits split into 4 bytes (MSB first) */
uint8_t  newKey[4]     = {0};

uint8_t  timerValue;
uint8_t  msCount  = 0;
char     pulseCount = 0;

/* ---------- Timer-0 ISR – 1 ms ticker ---------- */
void timer0_isr(void) interrupt 1
{
    if (msCount < 50)
        ++msCount;

    TH0 = 0xFC;                 /* reload for 1 ms @ 11 059 200 Hz */
    TL0 = 0x67;
}

/* ---------- LED helpers ---------- */
void up   (void) { P2 = ~1; }
void left (void) { P2 = ~2; }
void right(void) { P2 = ~4; }
void down (void) { P2 = ~8; }

/* ---------- INT0 ISR – NEC frame decode ---------- */
void externalIntr0_ISR(void) interrupt 0
{
    timerValue = msCount;
    msCount    = 0;

    TH0 = 0xFC;                 /* restart 1 ms timer */
    TL0 = 0x67;

    ++pulseCount;

    /* --------- Start-of-Frame (9 ms + 4.5 ms) -------- */
    if (timerValue >= 50) {                     /* = 50 ms ? new frame                */
        pulseCount      = -2;                   /* skip the 2 header “pulses”         */
        bitPattern[0] = bitPattern[1] =
        bitPattern[2] = bitPattern[3] = 0;
    }
    /* --------- Data bits (bit 31 … bit 0) -------- */
    else if (pulseCount >= 0 && pulseCount < 32) {
        if (timerValue >= 2) {                  /* = 2 ms = logic 1 (else logic 0)    */
            uint8_t byteIdx = pulseCount >> 3;  /* 0-3                                 */
            uint8_t bitPos  = 7 - (pulseCount & 7);
            bitPattern[byteIdx] |= 1u << bitPos;
        }
    }
    /* --------- End-of-Frame - 32 data “pulses” read -------- */
    else if (pulseCount >= 32) {
        /* copy freshly-received code */
        newKey[0] = bitPattern[0];
        newKey[1] = bitPattern[1];
        newKey[2] = bitPattern[2];
        newKey[3] = bitPattern[3];
        pulseCount = 0;

        /* --------- Command decode (ignore first byte = 0x00) -------- */
        if (newKey[1] == 0xFF && newKey[2] == 0x18 && newKey[3] == 0xE7)      up();
        else if (newKey[1] == 0xFF && newKey[2] == 0x10 && newKey[3] == 0xEF) left();
        else if (newKey[1] == 0xFF && newKey[2] == 0x5A && newKey[3] == 0xA5) right();
        else if (newKey[1] == 0xFF && newKey[2] == 0x4A && newKey[3] == 0xB5) down();
    }
}

/* ---------- main ---------- */
void main(void)
{
    TMOD |= 0x01;      /* Timer-0 mode-1 (16-bit)    */
    TH0  = 0xFC;       /* 1 ms preload               */
    TL0  = 0x67;
    TR0  = 1;          /* start Timer-0              */
    ET0  = 1;          /* enable Timer-0 interrupt   */

    IT0  = 1;          /* INT0 on falling edge       */
    EX0  = 1;          /* enable INT0                */

    EA   = 1;          /* global interrupt enable    */

    while (1) {
        /* main loop intentionally empty */
    }
}
