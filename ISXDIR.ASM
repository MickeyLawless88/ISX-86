	PAGE	60,132
	TITLE	ISXDIR - directory with exact file sizes (8086/MS-DOS)
;=======================================================================
; ISXDIR.ASM -- MS-DOS version of ISXDIR (ISX build).
;
; Same output as the CP/M original: header, files sorted by name, two
; per line as "NAME    .EXT  nnnnk nnnnnnn", then a totals line.  The
; CP/M version read directory extents and the disk parameter block;
; here MS-DOS FCB search (functions 11H/12H, same wildcard rules as
; CP/M) supplies the names and exact sizes, and the drive's cluster
; size takes the place of the CP/M block size for the "k" column.
; There are no user areas on MS-DOS, so the user shown is always 0.
;
; Usage:  ISXDIR [d:][filespec]
; Assemble: MASM ISXDIR;   Link: LINK ISXDIR;
;=======================================================================
CR	EQU	0DH
LF	EQU	0AH
FNPL	EQU	2			; files per line
MAXF	EQU	1024			; table entries
ESIZ	EQU	16			; entry: name(11) pad(1) size(4)

CODE	SEGMENT
	ASSUME	CS:CODE,DS:CODE,ES:CODE,SS:STK
START:	MOV	AX,CS			; copy the parsed FCB from the PSP
	MOV	DS,AX
	MOV	SI,5CH
	MOV	DI,OFFSET SFCB
	MOV	CX,12
CP1:	MOV	AL,ES:[SI]
	MOV	[DI],AL
	INC	SI
	INC	DI
	LOOP	CP1
	PUSH	DS
	POP	ES
	MOV	DX,OFFSET DTA
	MOV	AH,1AH
	INT	21H
	MOV	DX,OFFSET HEADER
	CALL	PRINT
	MOV	AH,19H			; drive letter
	INT	21H
	MOV	DL,SFCB
	OR	DL,DL
	JZ	DR1
	MOV	AL,DL
	DEC	AL
DR1:	MOV	DRV,AL
	ADD	AL,'A'
	CALL	TYPEA
	MOV	DX,OFFSET USRMSG
	CALL	PRINT
	MOV	AL,'0'			; user 0
	CALL	TYPEA
	CALL	CRLF
	CALL	CRLF
	MOV	DL,DRV			; cluster size in bytes
	INC	DL
	MOV	AH,36H
	INT	21H
	CMP	AX,0FFFFH
	JNE	DR2
	MOV	AX,1
	MOV	CX,1024
DR2:	MUL	CX
	MOV	CLUS,AX
	CMP	SFCB+1,' '		; no mask: *.*
	JNE	DR4
	CMP	SFCB+9,' '
	JNE	DR4
	MOV	DI,OFFSET SFCB+1
	MOV	AL,'?'
	MOV	CX,11
	REP	STOSB
DR4:	CALL	CFNT
	CMP	FNTC,0
	JE	EXIT
	CALL	SFNT
	CALL	PFNT
	CALL	CRLF
	CALL	CRLF
	MOV	AX,FNTC
	MOV	TYPN,0
	CALL	HLDEC
	MOV	DX,OFFSET STR2
	CALL	PRINT
	MOV	AX,TSIZE
	CALL	HLDEC
	MOV	DX,OFFSET STR3
	CALL	PRINT
EXIT:	MOV	AX,4C00H
	INT	21H

; collect matching files into FNT
CFNT:	MOV	FNTC,0
	MOV	DI,OFFSET FNT
	MOV	DX,OFFSET SFCB
	MOV	AH,11H
	INT	21H
	OR	AL,AL
	JZ	CF1
	MOV	DX,OFFSET NOFILE
	JMP	PRINT
CF1:	CMP	FNTC,MAXF
	JAE	CF2
	MOV	SI,OFFSET DTA+1		; name + ext
	MOV	CX,11
	REP	MOVSB
	MOV	BYTE PTR [DI],0
	ADD	DI,5			; size filled in by GETSZ
	INC	FNTC
CF2:	MOV	DX,OFFSET SFCB
	MOV	AH,12H
	INT	21H
	OR	AL,AL
	JZ	CF1
	; second pass: exact size of each file via handle FindFirst
	MOV	DX,OFFSET DTA2
	MOV	AH,1AH
	INT	21H
	MOV	SI,OFFSET FNT
	MOV	BX,FNTC
GS1:	OR	BX,BX
	JZ	GS9
	PUSH	SI
	MOV	DI,OFFSET PBUF		; "d:NAME.EXT",0
	MOV	AL,DRV
	ADD	AL,'A'
	STOSB
	MOV	AL,':'
	STOSB
	MOV	CX,8
GS2:	LODSB
	CMP	AL,' '
	JE	GS3
	STOSB
GS3:	LOOP	GS2
	MOV	AL,'.'
	STOSB
	MOV	CX,3
GS4:	LODSB
	CMP	AL,' '
	JE	GS5
	STOSB
GS5:	LOOP	GS4
	XOR	AL,AL
	STOSB
	POP	SI
	MOV	DX,OFFSET PBUF
	MOV	CX,0
	MOV	AH,4EH
	INT	21H
	MOV	AX,0
	MOV	DX,0
	JC	GS6
	MOV	AX,WORD PTR DTA2+1AH
	MOV	DX,WORD PTR DTA2+1CH
GS6:	MOV	[SI+12],AX
	MOV	[SI+14],DX
	ADD	SI,ESIZ
	DEC	BX
	JMP	GS1
GS9:	RET

; bubble sort of FNT by name
SFNT:	MOV	CX,FNTC
	DEC	CX
	JZ	SF5
SF1:	PUSH	CX
	MOV	BX,OFFSET FNT
SF2:	MOV	SI,BX
	LEA	DI,[BX+ESIZ]
	PUSH	CX
	MOV	CX,11
	REPE	CMPSB
	POP	CX
	JBE	SF4
	MOV	SI,BX			; swap
	PUSH	CX
	MOV	CX,ESIZ
SF3:	MOV	AL,[SI]
	XCHG	AL,[SI+ESIZ]
	MOV	[SI],AL
	INC	SI
	LOOP	SF3
	POP	CX
SF4:	ADD	BX,ESIZ
	LOOP	SF2
	POP	CX
	LOOP	SF1
SF5:	RET

; print the table, FNPL entries per line
PFNT:	MOV	TSIZE,0
	MOV	SI,OFFSET FNT
	XOR	BX,BX			; entry index
PF1:	CMP	BX,FNTC
	JAE	PF4
	OR	BX,BX
	JZ	PF3
	MOV	AX,BX
	XOR	DX,DX
	MOV	CX,FNPL
	DIV	CX
	OR	DX,DX
	JNZ	PF2
	CALL	CRLF
	JMP	SHORT PF3
PF2:	MOV	DX,OFFSET STR1
	CALL	PRINT
PF3:	PUSH	BX
	PUSH	SI
	CALL	WFNC
	POP	SI
	POP	BX
	ADD	SI,ESIZ
	INC	BX
	JMP	PF1
PF4:	RET

; display one entry at SI
WFNC:	MOV	CX,11
WF1:	MOV	AL,[SI]
	AND	AL,7FH
	CALL	TYPEA
	INC	SI
	CMP	CX,4
	JNE	WF2
	MOV	AL,'.'
	CALL	TYPEA
WF2:	LOOP	WF1
	INC	SI			; pad byte
	MOV	AX,[SI]			; size -> SZL/SZH
	MOV	SZL,AX
	MOV	AX,[SI+2]
	MOV	SZH,AX
	; k = clusters * cluster size / 1024, rounded up
	MOV	AX,SZL
	MOV	DX,SZH
	MOV	CX,CLUS
	ADD	AX,CX
	ADC	DX,0
	SUB	AX,1
	SBB	DX,0
	CMP	DX,CX			; avoid divide overflow
	JB	WF3
	MOV	DX,CX
	DEC	DX
WF3:	DIV	CX			; clusters
	MUL	CX			; bytes allocated
	ADD	AX,1023
	ADC	DX,0
	MOV	CX,1024
	CMP	DX,CX
	JB	WF4
	MOV	DX,CX
	DEC	DX
WF4:	DIV	CX
	ADD	TSIZE,AX
	MOV	TYPN,' '
	CALL	HLDEC
	MOV	AL,'k'
	CALL	TYPEA
	MOV	AL,' '
	CALL	TYPEA
	MOV	AX,SZL
	MOV	DX,SZH
	JMP	LDEC

; AX as 5 places, leading TYPN (0 = suppressed)
HLDEC:	MOV	BX,OFFSET POW10
	MOV	LEAD,0
HD1:	MOV	CX,[BX]
	CMP	CX,1
	JE	HD4
	XOR	DX,DX
	DIV	CX
	PUSH	DX
	OR	AL,AL
	JNZ	HD3
	CMP	LEAD,0
	JNE	HD3
	MOV	AL,TYPN
	OR	AL,AL
	JZ	HD2
	CALL	TYPEA
	JMP	SHORT HD2
HD3:	MOV	LEAD,1
	ADD	AL,'0'
	CALL	TYPEA
HD2:	POP	AX
	ADD	BX,2
	JMP	HD1
HD4:	ADD	AL,'0'
	JMP	TYPEA
POW10	DW	10000,1000,100,10,1

; DX:AX as 7 places, leading blanks
LDEC:	MOV	CX,7
	MOV	DI,OFFSET DIGS+6
LD1:	PUSH	CX
	MOV	CX,10			; DX:AX / 10
	MOV	BX,AX
	MOV	AX,DX
	XOR	DX,DX
	DIV	CX
	XCHG	AX,BX
	DIV	CX
	XCHG	DX,BX			; DX = high quotient, BX = remainder
	ADD	BL,'0'
	MOV	[DI],BL
	DEC	DI
	POP	CX
	LOOP	LD1
	MOV	SI,OFFSET DIGS
	MOV	CX,6
LD2:	CMP	BYTE PTR [SI],'0'
	JNE	LD3
	MOV	BYTE PTR [SI],' '
	INC	SI
	LOOP	LD2
LD3:	MOV	SI,OFFSET DIGS
	MOV	CX,7
LD4:	LODSB
	CALL	TYPEA
	LOOP	LD4
	RET

PRINT:	MOV	AH,9
	INT	21H
	RET
CRLF:	MOV	AL,CR
	CALL	TYPEA
	MOV	AL,LF
TYPEA:	PUSH	AX
	PUSH	DX
	MOV	DL,AL
	MOV	AH,2
	INT	21H
	POP	DX
	POP	AX
	RET

STR1	DB	'     $'
STR2	DB	' file(s), total size = $'
STR3	DB	'k bytes.',CR,LF,'$'
HEADER	DB	CR,LF,'Directory for drive $'
USRMSG	DB	':, user $'
NOFILE	DB	'No such file(s).',CR,LF,'$'
DRV	DB	0
TYPN	DB	0
LEAD	DB	0
CLUS	DW	0
FNTC	DW	0
TSIZE	DW	0
SZL	DW	0
SZH	DW	0
DIGS	DB	7 DUP(0)
SFCB	DB	37 DUP(0)
DTA	DB	64 DUP(0)
DTA2	DB	64 DUP(0)
PBUF	DB	32 DUP(0)
FNT	DB	MAXF*ESIZ DUP(0)
CODE	ENDS
STK	SEGMENT	STACK
	DW	256 DUP(0)
STK	ENDS
	END	START
