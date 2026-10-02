	PAGE	60,132
	TITLE	SETEOF - set exact end of file (8086/MS-DOS)
;=======================================================================
; SETEOF.ASM -- MS-DOS version of the ISX 1.4 SETEOF utility.
;
; The CP/M original read the last 128-byte record of the file, counted
; the ^Z (1AH) bytes at its end and stored that count in the FCB (S1)
; for ISX's patched BDOS, which then reported the exact file length to
; ISIS programs.  MS-DOS keeps exact lengths itself, so this version
; truncates the file by the same count instead.
;
; Usage:  SETEOF file        (silently does nothing if the file is
;                             missing or empty, as the original)
; Assemble: MASM SETEOF;   Link: LINK SETEOF;
;=======================================================================
CODE	SEGMENT
	ASSUME	CS:CODE,DS:CODE,ES:CODE,SS:STK
START:	MOV	AX,CS
	MOV	DS,AX
	MOV	SI,81H			; file name from the command tail
	MOV	DI,OFFSET FNAME
	XOR	CX,CX
	MOV	CL,ES:[80H]
SE1:	JCXZ	SE3
	MOV	AL,ES:[SI]
	INC	SI
	DEC	CX
	CMP	AL,' '
	JE	SE2
	CMP	AL,9
	JE	SE2
	CMP	AL,CR
	JE	SE3
	MOV	[DI],AL
	INC	DI
	JMP	SE1
SE2:	CMP	DI,OFFSET FNAME		; skip leading blanks only
	JE	SE1
SE3:	MOV	BYTE PTR [DI],0
	CMP	DI,OFFSET FNAME
	JNE	SE3A
	JMP	EXIT
SE3A:
	PUSH	DS
	POP	ES
	MOV	DX,OFFSET FNAME
	MOV	AX,3D02H		; open read/write
	INT	21H
	JNC	SE3B
	JMP	EXIT
SE3B:
	MOV	HAND,AX
	MOV	BX,AX
	MOV	AX,4202H		; size
	XOR	CX,CX
	XOR	DX,DX
	INT	21H
	MOV	SIZL,AX
	MOV	SIZH,DX
	MOV	CX,AX			; last record length = size mod 128,
	AND	CX,7FH			; or 128
	JNZ	SE4
	MOV	CX,128
SE4:	MOV	AX,SIZL
	OR	AX,SIZH
	JZ	CLOSE			; empty file
	MOV	RLEN,CX
	MOV	AX,SIZL			; seek to start of last record
	MOV	DX,SIZH
	SUB	AX,CX
	SBB	DX,0
	MOV	CX,DX
	MOV	DX,AX
	MOV	AX,4200H
	MOV	BX,HAND
	INT	21H
	MOV	CX,RLEN
	MOV	DX,OFFSET BUF
	MOV	AH,3FH
	INT	21H
	JC	CLOSE
	CMP	AX,RLEN
	JNE	CLOSE
	MOV	SI,OFFSET BUF		; count ^Z at the end of the record
	ADD	SI,RLEN
	XOR	CX,CX
SE5:	CMP	CX,RLEN
	JAE	SE6
	DEC	SI
	CMP	BYTE PTR [SI],1AH
	JNE	SE6
	INC	CX
	JMP	SE5
SE6:	JCXZ	CLOSE
	MOV	AX,SIZL			; truncate: seek to new end, write 0
	MOV	DX,SIZH
	SUB	AX,CX
	SBB	DX,0
	MOV	CX,DX
	MOV	DX,AX
	MOV	AX,4200H
	MOV	BX,HAND
	INT	21H
	XOR	CX,CX
	MOV	AH,40H
	INT	21H
CLOSE:	MOV	BX,HAND
	MOV	AH,3EH
	INT	21H
EXIT:	MOV	AX,4C00H
	INT	21H
CR	EQU	0DH
HAND	DW	0
SIZL	DW	0
SIZH	DW	0
RLEN	DW	0
FNAME	DB	128 DUP(0)
BUF	DB	128 DUP(0)
CODE	ENDS
STK	SEGMENT	STACK
	DW	128 DUP(0)
STK	ENDS
	END	START
