;*****************************************************************************
; File Name       : snake ir.asm
; Project Name    : 8051 Snake Game with Music Player, Score Counter, and Remote Input Handling
; Authors         : Elyas Al-Amri, Ahmad Al-Moslimani, Ejmen Al-Ubejdij
; Course          : CPEG300 - Embedded Systems Design
; Instructor      : Bo Wang
; Date            : April 2025
;*****************************************************************************
; Description:
;   This program implements a Snake game on an 8051 microcontroller with the
;   following features:
;   - Game displayed on an 8x8 LED matrix using 74HC595 shift registers
;   - IR remote control for snake direction input (up, down, left, right)
;   - Score display on 7-segment displays
;   - Background music playback (Undertale theme)
;   - Self-contained game logic with apple generation and collision detection
;
; Hardware Requirements:
;   - 8051 compatible microcontroller
;   - 8x8 LED matrix connected via 74HC595 shift registers
;   - 7-segment displays for score (2 digits)
;   - IR receiver module connected to INT0
;   - Buzzer connected to P2.5
;   - Clock speed: [Your clock speed] MHz
;
; I/O Configuration:
;   - P3.4: DATA_PIN (Serial data to 74HC595)
;   - P3.6: CLOCK_PIN (Shift register clock)
;   - P3.5: LATCH_PIN (Storage register clock)
;   - P2.5: BUZZ_PIN (Piezo buzzer output)
;   - P0: Used for cathode control of LED matrix and 7-segment display
;   - P2: Used for 7-segment selection
;   - INT0: IR receiver input
;
; Memory Usage:
;   - 20H-27H: LED matrix display buffer
;   - 28H: Game flags (bit addesses 40H-43H)
;   - 29H-39H: Game variables and counters
;   - 3AH-7AH: Snake position data
;
; Register Banks Usage:
;   - Bank 0: default bank for main operations
;   - Bank 1: Game Variable Registers
;   - Bank 2: IR Module Variable Registers
;
; Revision History:
;   - 4th April 2025: Initial implementation (game, music, input with buttons, score counter)
;   - 28th April: Change input to remote control (IR module) (yeah it was that hard)
;*****************************************************************************

; assembly definitions

; 74hc595 shift register pins
DATA_PIN	BIT	P3.4	; serial data input
CLOCK_PIN	BIT	P3.6	; shift register clock input
LATCH_PIN	BIT	P3.5	; storage register clock input

; other I/O pins
BUZZ_PIN	BIT	P2.5	; buzzer output

; constants
TICKS_PER_GAME_CYCLE	SET	10D	; game loop cycle duration (in ticks)
ONE_HOT_CODE_MAP	SET	0400H	; one-hot display encoding
BCD_MAP	SET	0410H		; binary-coded decimal map
NOTES_MAP	SET	0420H	; melody notes
DURATIONS_MAP	SET	04D6H	; note durations
NOTES_MAP_LENGTH	SET	182D	; length of melody

; global variables
BOARD_DATA_POINTER	SET	20H ; board occupies 20H-27H
SNAKE_DATA_POINTER	SET	3AH ; snake occupies 3AH-7AH
SNAKE_DATA_LENGTH	SET	29H
SNAKE_LENGTH_TEMP	SET	2AH

; music playback registers
NOTE_INDEX	SET	2BH
NOTE_H	SET	2CH
NOTE_L	SET	2DH
DURATION_INDEX	SET	2EH
DURATION_REGISTER	SET	2FH
P2_SHADOW	SET	30H	; used to avoid conflicts with render_score

; IR module temp variables
MSCOUNT	SET	31H ; milliseconds counter
PULSECOUNT	SET	32H ; ir pulses counter
BYTEIDX	SET	33H
BITPOS	SET	34H
ORAMT	SET	35H
BITPATTERN	SET	36H ; 32 bit pattern of received signal, allocated from 36H-39H

; global flags (all in register 28H)
DISPLAY_APPLE	BIT	40H
SNAKE_INC	BIT	41H
SHOULD_REST	BIT	42H
TEMP_C		BIT	43H

ROW_REGISTER	SET	R3	; used to rotate the cathode
TICK_REGISTER	SET	R7	; used to control cycle rate

; bank 1 (gameplay logic)
AX	SET	R2		; apple x position
AY	SET	R3		; apple y position
PX	SET	R4		; snake head x position
PY	SET	R5		; snake head y position
VX	SET	R6		; snake x velocity
VY	SET	R7		; snake y velocity

	ORG	0000H
	JMP	MAIN

; IVT mapping
	ORG	0003H
	JMP	INPUT0_ISR
	ORG	000BH
	JMP	TIMER0_ISR
	ORG	001BH
	JMP	TIMER1_ISR
	ORG	002BH
	JMP	TIMER2_ISR

TIMER0_ISR:
	CALL	PLAY_MUSIC	; call the music manager every tick
	DJNZ	TICK_REGISTER, SKIP_TIMER0_ISR	; wait for x ticks per cycle
	MOV	TICK_REGISTER, #TICKS_PER_GAME_CYCLE
	CALL	GAME_CYCLE
SKIP_TIMER0_ISR:
	CALL	START_TIMER0	; restart timer
	RETI

START_TIMER0:
	MOV	TH0, #0C5H	; 15ms
	MOV	TL0, #068H
	SETB	TR0
	RET

TIMER1_ISR:
	JB	SHOULD_REST, TIMER1_ISR_REST	; if rest: skip
	CPL	BUZZ_PIN	; oscillate the buzzer
	SJMP	TIMER1_ISR_DONE

TIMER1_ISR_REST:
	SETB	BUZZ_PIN	; mostly for aesthetic

TIMER1_ISR_DONE:
;	CALL START_TIMER1 ; oddly enough, the led matrix glithes if this gets called
	MOV	TH1, NOTE_H	; set preload of note freq
	MOV	TL1, NOTE_L
	SETB	TR1		; enable timer
	MOV	P2_SHADOW, P2	; shadow copy of P2
	RETI

START_TIMER1:
	MOV	TH1, NOTE_H	; set preload of note freq
	MOV	TL1, NOTE_L
	SETB	TR1		; enable timer
	RET

TIMER2_ISR:
	CLR	TF2 ; oddly enough, not cleared by default, resulting in infinite interrupts
	PUSH	ACC
	PUSH	PSW

	MOV	TEMP_C, C
	CLR	C

	MOV	A, msCount
	SUBB	A, #032H
	MOV	A, #080H
	SUBB	A, #080H
	JNC	SKIP_TIMER2_ISR

	INC	msCount
SKIP_TIMER2_ISR:
	MOV	C, TEMP_C
	POP	PSW
	POP	ACC
	RETI

INIT_TIMER2:
	MOV	T2CON, #00H	;Clear T2CON register first
	MOV	T2MOD, #00H	;T2OE=0 (No clock output), DCEN=0 (Count up)

	MOV	RCAP2H, #0FCH	;High byte of reload value
	MOV	RCAP2L, #067H	;Low byte of reload value

	MOV	TH2, #0FCH	;High byte initial value
	MOV	TL2, #067H	;Low byte initial value

	SETB	TR2
	RET

; ISR and IR module responsible for handling remote signals
; very obscure as it was generated from c51 code
; refer to ir.c for more
INPUT0_ISR:
	PUSH	ACC
	PUSH	PSW
	MOV	PSW, #00H
	CLR	RS0
	SETB	RS1
	MOV	TH2, #0FCH
	MOV	TL2, #067H
	INC	PULSECOUNT
	MOV	R7, MSCOUNT
	MOV	R6, #00H
	CLR	C
	MOV	A, R7
	SUBB	A, #032H
	MOV	A, #080H
	SUBB	A, #080H
	JC	C0007

	MOV	PULSECOUNT, #0FEH
	MOV	BITPATTERN, #00H
	MOV	BITPATTERN+01H, #00H
	MOV	BITPATTERN+02H, #00H
	MOV	BITPATTERN+03H, #00H
	LJMP	C0008
C0007:

	MOV	R5, PULSECOUNT
	MOV	A, R5
	RLC	A
	SUBB	A, ACC
	MOV	R4, A
	CLR	C
	XRL	A, #080H
	SUBB	A, #080H
	JC	C0009
	MOV	A, R5
	SUBB	A, #020H
	MOV	A, R4
	XRL	A, #080H
	SUBB	A, #080H
	JNC	C0009

	CLR	C
	MOV	A, R7
	SUBB	A, #02H
	MOV	A, R6
	XRL	A, #080H
	SUBB	A, #080H
	JNC	$+5H
	LJMP	C0008

	MOV	R0, #03H
	MOV	A, PULSECOUNT
C0025:
	MOV	C, ACC.7
	RRC	A
	DJNZ	R0, C0025
	MOV	BYTEIDX, A

	MOV	A, PULSECOUNT
	ANL	A, #07H
	MOV	R7, A
	CLR	C
	MOV	A, #07H
	SUBB	A, R7

	MOV	BITPOS, A

	MOV	R7, A
	MOV	R0, A
	MOV	A, #01H
	INC	R0
	SJMP	C0027
C0026:
	CLR	C
	RLC	A
C0027:
	DJNZ	R0, C0026
	MOV	ORAMT, A

	MOV	A, #LOW BITPATTERN
	ADD	A, BYTEIDX
	MOV	R0, A
	MOV	A, @R0
	ORL	A, ORAMT
	MOV	@R0, A


	SJMP	C0008
C0009:

	MOV	R7, PULSECOUNT
	MOV	A, R7
	RLC	A
	SUBB	A, ACC
	MOV	R6, A
	CLR	C
	MOV	A, R7
	SUBB	A, #020H
	MOV	A, R6
	XRL	A, #080H
	SUBB	A, #080H
	JC	C0008

	MOV	PULSECOUNT, #00H

	MOV	A, BITPATTERN+01H
	CPL	A
	JNZ	C0014

	MOV	R7, BITPATTERN+02H
	MOV	R6, A
	MOV	A, R7
	XRL	A, #018H
	JNZ	C0015
	MOV	A, BITPATTERN+03H
	XRL	A, #0E7H
	JNZ	C0015
	LCALL	UP
	SJMP	C0008
C0015:

	MOV	A, R7
	XRL	A, #010H
	ORL	A, R6
	JNZ	C0017
	MOV	A, BITPATTERN+03H
	XRL	A, #0EFH

	JNZ	C0017
	LCALL	LEFT
	SJMP	C0008
C0017:

	MOV	A, BITPATTERN+02H
	XRL	A, #05AH
	JNZ	C0019
	MOV	A, BITPATTERN+03H
	XRL	A, #0A5H
	JNZ	C0019
	LCALL	RIGHT
	SJMP	C0008
C0019:

	MOV	A, BITPATTERN+02H
	XRL	A, #04AH
	JNZ	C0008
	MOV	A, BITPATTERN+03H
	XRL	A, #0B5H
	JNZ	C0008
	LCALL	DOWN

C0008:

	MOV	MSCOUNT, #00H

C0014:
	POP	PSW
	POP	ACC
	RETI

; snake direction change functions
UP:
	PUSH	PSW
	CLR	RS1
	SETB	RS0
	MOV	VX, #0H
	MOV	VY, #1H
	POP	PSW
	RET

LEFT:
	PUSH	PSW
	CLR	RS1
	SETB	RS0
	MOV	VX, #0FFH
	MOV	VY, #0H
	POP	PSW
	RET

RIGHT:
	PUSH	PSW
	CLR	RS1
	SETB	RS0
	MOV	VX, #1H
	MOV	VY, #0H
	POP	PSW
	RET

DOWN:
	PUSH	PSW
	CLR	RS1
	SETB	RS0
	MOV	VX, #0H
	MOV	VY, #0FFH
	POP	PSW
	RET

; the main loop of the game
; uses bank 1
GAME_CYCLE:
	; save context
	PUSH	A
	PUSH	B
	PUSH	PSW

	SETB	RS0		; use bank 1
	CLR	RS1

	CALL	MOVE_PLAYER
	CALL	SHIFT_INTO_SNAKE
	CALL	CHECK_APPLE
	CALL	DRAW_BOARD

	; restore context
	POP	PSW
	POP	B
	POP	A

	RET

MOVE_PLAYER:
	; PX += VX
	XCH	A, PX
	ADD	A, VX
	ANL 	A, #07H ; A %= 8
	XCH	A, PX

	; PY += VY
	XCH	A, PY
	ADD	A, VY
	ANL 	A, #07H ; A %= 8
	XCH	A, PY

	RET

; reset the board before rendering the next frame
RESET_BOARD:
	MOV	BOARD_DATA_POINTER, #0
	MOV	BOARD_DATA_POINTER+1H, #0
	MOV	BOARD_DATA_POINTER+2H, #0
	MOV	BOARD_DATA_POINTER+3H, #0
	MOV	BOARD_DATA_POINTER+4H, #0
	MOV	BOARD_DATA_POINTER+5H, #0
	MOV	BOARD_DATA_POINTER+6H, #0
	MOV	BOARD_DATA_POINTER+7H, #0
	RET

; insert PX, PY into the beginning of the snake array
SHIFT_INTO_SNAKE:
	MOV	SNAKE_LENGTH_TEMP, SNAKE_DATA_LENGTH
	DEC	SNAKE_LENGTH_TEMP

; mechanism for inserting an element at the beginning of an array
SHIFT_INTO_SNAKE_LOOP:
	MOV	A, SNAKE_LENGTH_TEMP
	ADD	A, #SNAKE_DATA_POINTER
	MOV	R0, A
	MOV	R1, A
	DEC	R1
	MOV	A, @R1
	MOV	@R0, A
	DJNZ	SNAKE_LENGTH_TEMP, SHIFT_INTO_SNAKE_LOOP

	MOV	A, PY
	SWAP	A
	ORL	A, PX
	MOV	R0, #SNAKE_DATA_POINTER
	MOV	@R0, A

	RET

; redraws the entire board for rendering
DRAW_BOARD:
	CALL	RESET_BOARD
	MOV	SNAKE_LENGTH_TEMP, SNAKE_DATA_LENGTH
	JNB	SNAKE_INC, DRAW_BOARD_LOOP	; the flag indicates not to draw the last cell for one cycle
	DEC	SNAKE_LENGTH_TEMP
	CLR	SNAKE_INC
DRAW_BOARD_LOOP:
	; draw snake cells
	MOV	R0, SNAKE_LENGTH_TEMP
	DEC	R0
	MOV	A, R0
	ADD	A, #SNAKE_DATA_POINTER
	MOV	R0, A
	MOV	A, @R0
	MOV	R0, A

	ANL	A, #0FH
	ADD	A, #BOARD_DATA_POINTER
	MOV	R1, A
	MOV	B, @R1

	MOV	A, R0
	SWAP	A
	ANL	A, #0FH
	MOV	DPTR, #ONE_HOT_CODE_MAP
	MOVC	A, @A+DPTR
	ORL	A, B
	MOV	@R1, A

	DJNZ	SNAKE_LENGTH_TEMP, DRAW_BOARD_LOOP

	; blinking effect (for distinguishability)
	CPL	DISPLAY_APPLE
	JNB	DISPLAY_APPLE, DRAW_BOARD_DONE

	; draw apple
	MOV	A, AX
	ADD	A, #BOARD_DATA_POINTER
	MOV	R1, A		; R1 = row pointer

	MOV	B, @R1		; get existing row content

	MOV	A, AY
	MOV	DPTR, #ONE_HOT_CODE_MAP
	MOVC	A, @A+DPTR	; A = column bitmask

	ORL	A, B
	MOV	@R1, A		; store updated row with apple bit added
DRAW_BOARD_DONE:
	RET

; check if snake head is on the apple
CHECK_APPLE:
	MOV	A, PX
	XRL	A, AX
	JNZ	CHECK_APPLE_DONE	; if PX != AX, skip

	MOV	A, PY
	XRL	A, AY
	JNZ	CHECK_APPLE_DONE	; if PY != AY, skip

	; match
	INC	SNAKE_DATA_LENGTH
	SETB	SNAKE_INC	; don't draw last cell
	CALL	GENERATE_NEW_APPLE

CHECK_APPLE_DONE:
	RET

; a function to generate a new apple location
; it uses timer 0 and timer 1 current value as pseudo RNG
GENERATE_NEW_APPLE:
	MOV	A, TL0		; pseudo RNG
	ANL 	A, #07H ; A %= 8
	MOV	AX, A

	MOV	A, TL1
	ANL 	A, #07H ; A %= 8
	MOV	AY, A

	; combine AX, AY
	MOV	A, AY
	SWAP	A
	ORL	A, AX
	MOV	R1, A

	MOV	B, SNAKE_DATA_LENGTH
	MOV	R0, #SNAKE_DATA_POINTER

CHECK_APPLE_COLLISION_LOOP:
	MOV	A, @R0
	XRL	A, R1
	JZ	GENERATE_NEW_APPLE
	INC	R0
	DJNZ	B, CHECK_APPLE_COLLISION_LOOP

	RET

; music player loop body 
PLAY_MUSIC:
	DJNZ	DURATION_REGISTER, PLAY_MUSIC_DONE	; skip if duration didn't finish
	PUSH	A		; save context
	PUSH	B

PLAY_MUSIC_REPEAT:
	; if we were resting, we have finished resting; otherwise, now rest
	CPL	SHOULD_REST

	JB	SHOULD_REST, SKIP_NEXT_NOTE
	CALL	NEXT_NOTE
SKIP_NEXT_NOTE:
	CALL	NEXT_DURATION
	INC	DURATION_REGISTER
	DJNZ	DURATION_REGISTER, PLAY_MUSIC_CLEAR	; don't want to use CJNE
	SJMP	PLAY_MUSIC_REPEAT	; skip 0 duration (usually happens with rests)
PLAY_MUSIC_CLEAR:
	POP	B		; restore context
	POP	A
PLAY_MUSIC_DONE:
	RET

NEXT_NOTE:
	MOV	DPTR, #NOTES_MAP

	MOV	A, NOTE_INDEX
	MOVC	A, @A+DPTR
	MOV	NOTE_H, A

	INC	NOTE_INDEX
	MOV	A, NOTE_INDEX
	MOVC	A, @A+DPTR
	MOV	NOTE_L, A

	INC	NOTE_INDEX
	MOV	A, NOTE_INDEX
	MOV	B, #NOTES_MAP_LENGTH
	DIV	AB
	MOV	NOTE_INDEX, B

	RET

NEXT_DURATION:
	MOV	DPTR, #DURATIONS_MAP
	MOV	A, DURATION_INDEX
	MOVC	A, @A+DPTR
	MOV	DURATION_REGISTER, A

	INC	DURATION_INDEX
	MOV	A, DURATION_INDEX
	MOV	B, #NOTES_MAP_LENGTH
	DIV	AB
	MOV	DURATION_INDEX, B

	RET


MAIN:
	MOV	SP, #0A0H	; shift the SP to allow use of bank 1, 2 registers
	CALL	SETUP

RENDER_LOOP:
	CALL	RENDER_BOARD
	CALL	ROTATE_CATHODE
	CALL	RENDER_SCORE
	SJMP	RENDER_LOOP

SETUP:
	MOV	TMOD, #11H	;setup timers
	MOV	IE, #0FFH

	; enable interrupts
	SETB	EX0
	SETB	ET0
	SETB	ET1
	SETB	ET2
	SETB	EA

	SETB	IT0		; falling edge for external interrupts
	SETB	IT1
	SETB	PT1		; priority to notes player

	; initialize values
	MOV	P1, #0F8H
	MOV	TICK_REGISTER, #TICKS_PER_GAME_CYCLE
	MOV	SNAKE_DATA_LENGTH, #3H

	SETB	RS0
	MOV	AX, #4H
	MOV	AY, #4H
	MOV	VX, #1H
	MOV	VY, #0H
	CLR	RS0

	MOV	P2_SHADOW, #0FFH
	CALL	NEXT_NOTE
	CALL	NEXT_DURATION
	CALL	START_TIMER0
	CALL	START_TIMER1
	CALL	INIT_TIMER2

	RET

RENDER_BOARD:
	MOV	A, ROW_REGISTER
	ADD	A, #BOARD_DATA_POINTER
	MOV	R0, A
	MOV	A, @R0

	MOV	P0, #0FFH	; reset cathode
	CALL	SEND_TO_595

	INC	ROW_REGISTER
	XCH	A, ROW_REGISTER
	ANL 	A, #07H ; A %= 8
	XCH	A, ROW_REGISTER	; ROW_REGISTER = (ROW_REGISTER + 1) MOD 8

	RET

ROTATE_CATHODE:
	MOV	A, ROW_REGISTER
	MOV	R2, #0FBH
	XCH	A, R2
	INC	R2
ROTATE_CATHODE_LOOP:
	RR	A
	DJNZ	R2, ROTATE_CATHODE_LOOP

	MOV	P0, A
	CALL	CATHODE_DELAY
	RET

RENDER_SCORE:
	PUSH	P0		; save cathode of led matrix

	MOV	A, SNAKE_DATA_LENGTH
	CLR	C
	SUBB	A, #3		; score = snake length - 3
	CALL	BIN2BCD		; R0 and R1 contain BCDs of score
	MOV	DPTR, #BCD_MAP
	MOV	R1, A
	MOV	R0, B

	MOV	A, P2_SHADOW	; reading from P2 directly causes issues, so we use a shadow copy
	ORL	A, #00011100B
	MOV	P2, A		; select the last segment (ignore)

	MOV	A, R1
	MOVC	A, @A+DPTR	; map A to 7seg
	MOV	P0, A		; change 7seg

	MOV	A, P2_SHADOW
	ANL	A, #11100011B
	ORL	A, #00000100B
	MOV	P2, A		; select the second seg group

	MOV	A, P2_SHADOW
	ORL	A, #00011100B
	MOV	P2, A		; select the last segment (ignore)

	MOV	A, B
	MOVC	A, @A+DPTR
	MOV	P0, A

	MOV	A, P2_SHADOW
	ANL	A, #11100011B
	MOV	P2, A		; select the first seg group


	MOV	A, P2_SHADOW
	ORL	A, #00011100B
	MOV	P2, A		; select the last segment (ignore)

	POP	P0		; revert cathode
	RET


; series to parallel and then to 8x8 led matrix
SEND_TO_595:
	MOV	R6, #08H
SEND_LOOP:
	RLC	A
	MOV	DATA_PIN, C
	SETB	CLOCK_PIN
	NOP
	CLR	CLOCK_PIN
	NOP
	DJNZ	R6, SEND_LOOP
	SETB	LATCH_PIN
	NOP
	CLR	LATCH_PIN
	RET

; small delay function for the led matrix cathode
CATHODE_DELAY:
	MOV	R6, #04D
DEL:	MOV	R5, #0250D
	DJNZ	R5, $
	DJNZ	R6, DEL
	RET

; converts binary to BCD
BIN2BCD:
	MOV	B, #10D
	DIV	AB
	RET

	ORG	ONE_HOT_CODE_MAP ; easy way to get 2^A
	DB	01H, 02H, 04H, 08H, 010H, 020H, 040H, 080H, 0H
	ORG	BCD_MAP ; BCD to 7-Segment mapping
	DB	3FH, 06H, 5BH, 4FH, 66H, 6DH, 7DH, 07H, 7FH, 6FH

	ORG	NOTES_MAP ; melody of undertale
	DB	0F6H, 095H
	DB	0EDH, 02AH
	DB	0F1H, 0E4H
	DB	0F3H, 06EH
	DB	0F4H, 0CDH
	DB	0F3H, 06EH
	DB	0F4H, 0CDH
	DB	0F3H, 06EH
	DB	0F1H, 0E4H
	DB	0F1H, 00DH
	DB	0F1H, 0E4H
	DB	0F3H, 06EH
	DB	0EDH, 02AH
	DB	0F6H, 095H
	DB	0EDH, 02AH
	DB	0F1H, 0E4H
	DB	0F3H, 06EH
	DB	0F4H, 0CDH
	DB	0F3H, 06EH
	DB	0F4H, 0CDH
	DB	0F3H, 06EH
	DB	0F1H, 0E4H
	DB	0F1H, 00DH
	DB	0F1H, 0E4H
	DB	0F3H, 06EH
	DB	0F1H, 0E4H
	DB	0F6H, 095H
	DB	0EDH, 02AH
	DB	0F1H, 0E4H
	DB	0F3H, 06EH
	DB	0F4H, 0CDH
	DB	0F3H, 06EH
	DB	0F4H, 0CDH
	DB	0F3H, 06EH
	DB	0F1H, 0E4H
	DB	0F1H, 00DH
	DB	0F1H, 0E4H
	DB	0F3H, 06EH
	DB	0EDH, 02AH
	DB	0F6H, 095H
	DB	0EDH, 02AH
	DB	0F1H, 0E4H
	DB	0F3H, 06EH
	DB	0F4H, 0CDH
	DB	0F3H, 06EH
	DB	0F4H, 0CDH
	DB	0F3H, 06EH
	DB	0F1H, 0E4H
	DB	0F1H, 00DH
	DB	0F1H, 0E4H
	DB	0F3H, 06EH
	DB	0F1H, 0E4H
	DB	0F6H, 095H
	DB	0F6H, 095H
	DB	0F6H, 095H
	DB	0F6H, 095H
	DB	0F5H, 06EH
	DB	0F4H, 0CDH
	DB	0F5H, 06EH
	DB	0F6H, 095H
	DB	0F8H, 086H
	DB	0F6H, 095H
	DB	0F6H, 095H
	DB	0F6H, 095H
	DB	0F6H, 095H
	DB	0F6H, 095H
	DB	0F5H, 06EH
	DB	0F4H, 0CDH
	DB	0F5H, 06EH
	DB	0F6H, 095H
	DB	0EFH, 038H
	DB	0F3H, 06EH
	DB	0F4H, 0CDH
	DB	0F4H, 0CDH
	DB	0F4H, 0CDH
	DB	0F4H, 0CDH
	DB	0F4H, 0CDH
	DB	0F3H, 06EH
	DB	0F1H, 0E4H
	DB	0EFH, 038H
	DB	0F4H, 0CDH
	DB	0F4H, 0CDH
	DB	0F4H, 0CDH
	DB	0F4H, 0CDH
	DB	0F3H, 06EH
	DB	0F4H, 0CDH
	DB	0F6H, 095H
	DB	0F7H, 09CH
	DB	0F4H, 0CDH
	DB	0F1H, 0E4H
	DB	0F3H, 06EH

	ORG	DURATIONS_MAP ; note length / rest length periods of the melody
	DB	032H, 019H
	DB	00CH, 000H
	DB	00CH, 000H
	DB	006H, 013H
	DB	006H, 013H
	DB	006H, 000H
	DB	006H, 000H
	DB	006H, 006H
	DB	006H, 013H
	DB	026H, 00CH
	DB	00CH, 00CH
	DB	00CH, 00CH
	DB	04BH, 019H
	DB	032H, 019H
	DB	00CH, 000H
	DB	00CH, 000H
	DB	006H, 013H
	DB	006H, 013H
	DB	006H, 000H
	DB	006H, 000H
	DB	006H, 006H
	DB	006H, 013H
	DB	026H, 00CH
	DB	00CH, 00CH
	DB	00CH, 00CH
	DB	04BH, 019H
	DB	032H, 019H
	DB	00CH, 000H
	DB	00CH, 000H
	DB	006H, 013H
	DB	006H, 013H
	DB	006H, 000H
	DB	006H, 000H
	DB	006H, 006H
	DB	006H, 013H
	DB	026H, 00CH
	DB	00CH, 00CH
	DB	00CH, 00CH
	DB	04BH, 019H
	DB	032H, 019H
	DB	00CH, 000H
	DB	00CH, 000H
	DB	006H, 013H
	DB	006H, 013H
	DB	006H, 000H
	DB	006H, 000H
	DB	006H, 006H
	DB	006H, 013H
	DB	026H, 00CH
	DB	00CH, 00CH
	DB	00CH, 00CH
	DB	04BH, 019H
	DB	00CH, 00CH
	DB	00CH, 00DH
	DB	00CH, 00CH
	DB	00CH, 00CH
	DB	019H, 000H
	DB	019H, 000H
	DB	019H, 000H
	DB	032H, 000H
	DB	032H, 000H
	DB	064H, 019H
	DB	00CH, 00CH
	DB	00CH, 00CH
	DB	00CH, 00CH
	DB	00CH, 00CH
	DB	019H, 000H
	DB	019H, 000H
	DB	019H, 000H
	DB	064H, 04BH
	DB	00CH, 000H
	DB	00CH, 000H
	DB	00CH, 00CH
	DB	00CH, 00CH
	DB	00CH, 00CH
	DB	00CH, 00CH
	DB	019H, 000H
	DB	019H, 000H
	DB	019H, 000H
	DB	00CH, 026H
	DB	00CH, 00CH
	DB	00CH, 00CH
	DB	00CH, 00CH
	DB	019H, 000H
	DB	019H, 000H
	DB	019H, 000H
	DB	019H, 000H
	DB	096H, 000H
	DB	019H, 000H
	DB	019H, 000H
	DB	096H, 020H
	END
