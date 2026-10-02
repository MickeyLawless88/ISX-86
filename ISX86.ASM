			PAGE	60,132
			TITLE	ISX86 - ISIS-II INTERFACE FOR MS-DOS (8086)
;=======================================================================
; ISX86.ASM  --  ISIS-II interface (ISX) for the IBM PC / MS-DOS.
;
; 8086 rewrite of ISX.ASM (Digital Research ISIS-II INTERFACE VERS 1.4,
; Kaypro-patched version).  ISX ran ISIS-II 8080 programs (PLM80, ASM80,
; FORT80, LINK, LOCATE, ...) under CP/M by trapping their ISIS calls at
; 0040H and the Intellec monitor entries at F800H.  An 8086 cannot run
; 8080 code, so this version carries an 8080 interpreter; the ISIS layer
; reproduces ISX's behaviour on MS-DOS handle calls instead of the CP/M
; BDOS:  prompt "n>", internal commands DIR/ERA/TYPE/REN/DBUG, absolute
; OMF-80 loader (content >= 3100H, below MEMTOP), :CI: line buffer
; positioned after the command name, RESCAN, ISX error codes and the
; "ERROR nnn, AT USER PC xxxx" report.  EXIT returns to DOS.
;
; Assemble:  MASM ISX86;      Link:  LINK ISX86;
;
; Filename mapping:  :F0:-:F9: all map to the current DOS directory
; unless overridden with environment variables ISISF0 .. ISISF9, e.g.
;       SET ISISF1=B:
;       SET ISISF2=C:\PLM\
; Use FILES=20 (or more) in CONFIG.SYS.
;
; Usage:  ISX86              interactive ISIS command line
;         ISX86 command      run one ISIS command, then return to DOS
;=======================================================================
;
; 8080 register mapping inside the interpreter:
;       A=AL  F=AH (8080 PSW bits == 8086 LAHF/SAHF bits)
;       BC=CX  DE=DX  HL=BX  PC=SI  SP=BP  DS=ES=8080 64K memory segment
;
CR			EQU		0DH
LF			EQU		0AH
MEMTOP		EQU		0F7FFH			; returned by MEMCK (monitor page at F800H)
LDLOW		EQU		3100H			; lowest load address (as ISX)
STK80		EQU		3100H			; initial 8080 SP for a loaded program
NSLOT		EQU		10				; AFTN 0..9  (0=:CO: 1=:CI:)
PLEN		EQU		80				; DOS path buffer length
; slot types
ST_FREE		EQU		0
ST_DISK		EQU		1
ST_BB		EQU		2
ST_AUXI		EQU		3
ST_AUXO		EQU		4
ST_PRN		EQU		5
ST_CO		EQU		6
ST_CI		EQU		7
; trap numbers (ED nn)
TR_ISIS		EQU		0
TR_EXIT		EQU		13
TR_BRK		EQU		14

NXT			MACRO
			MOV		DI,WORD PTR [SI]
			INC		SI
			AND		DI,0FFH
			SHL		DI,1
			JMP		WORD PTR CS:OPTAB[DI]
			ENDM

			CODE	SEGMENT
			ASSUME	CS:CODE,DS:CODE,ES:NOTHING,SS:STK

;-----------------------------------------------------------------------
; Entry
;-----------------------------------------------------------------------
START:		MOV		AX,CS
			MOV		DS,AX
			MOV		PSPSEG,ES
			MOV		BX,SEG ZZZ		; shrink to our image
			SUB		BX,PSPSEG
			INC		BX
			MOV		AH,4AH
			INT		21H
			MOV		BX,1000H		; 64K for the 8080
			MOV		AH,48H
			INT		21H
			JNC		ST1
			MOV		DX,OFFSET MNOMEM
			MOV		AH,9
			INT		21H
			MOV		AX,4C01H
			INT		21H
ST1:		MOV		MEMSEG,AX
			MOV		ES,AX			; clear 8080 memory
			XOR		DI,DI
			MOV		CX,8000H
			XOR		AX,AX
			CLD
			REP		STOSW
			CALL	INSTRAP
			PUSH	DS				; ^C handler
			MOV		DX,OFFSET INT23
			MOV		AX,2523H
			INT		21H
			POP		DS
			CALL	GETENV
			MOV		AX,4400H		; is stdin a device?
			XOR		BX,BX
			INT		21H
			MOV		AL,0
			JC		ST2
			TEST	DL,80H
			JZ		ST2
			MOV		AL,1
ST2:		MOV		INDEV,AL
			MOV		DX,OFFSET LOGMSG
			CALL	PUTS
			CALL	TAILCMD			; DOS command tail -> one-shot
			JMP		CLI

MNOMEM		DB		'ISX86: NOT ENOUGH MEMORY',CR,LF,'$'
LOGMSG		DB		CR,LF,'ISIS-II INTERFACE VERS 1.4 (MS-DOS)',CR,LF,'$'

; install the trap stubs in 8080 memory (ES = MEMSEG)
INSTRAP:
			MOV		ES,MEMSEG
			; ED 0D  exit
			MOV		WORD PTR ES:[0000H],0DEDH
			; ED 0E  RST 7 break
			MOV		WORD PTR ES:[0038H],0EEDH
			; ED 00  ISIS
			MOV		WORD PTR ES:[0040H],00EDH
			; RET
			MOV		BYTE PTR ES:[0042H],0C9H
			MOV		DI,0F800H
			MOV		AL,1
IT1:		MOV		BYTE PTR ES:[DI],0EDH
			MOV		BYTE PTR ES:[DI+1],AL
			MOV		BYTE PTR ES:[DI+2],0C9H
			ADD		DI,3
			INC		AL
			CMP		AL,13
			JB		IT1
			RET

; ^C: remember it, let DOS continue
INT23:		MOV		CS:BRKFLG,1
			IRET

; read ISISF0..ISISF9 from the environment into DMAP
GETENV:		MOV		ES,PSPSEG
			MOV		ES,WORD PTR ES:[2CH]
			XOR		DI,DI
GE1:		CMP		BYTE PTR ES:[DI],0
			JNE		GE2
			RET
GE2:		MOV		SI,OFFSET ENVKEY
			MOV		BX,DI
			MOV		CX,5
GE3:		MOV		AL,ES:[BX]
			CMP		AL,[SI]
			JNE		GENX
			INC		BX
			INC		SI
			LOOP	GE3
			MOV		AL,ES:[BX]		; digit
			SUB		AL,'0'
			CMP		AL,9
			JA		GENX
			CMP		BYTE PTR ES:[BX+1],'='
			JNE		GENX
			ADD		BX,2
			MOV		AH,PLEN-14
			MUL		AH
			ADD		AX,OFFSET DMAP
			MOV		SI,AX
			MOV		CX,PLEN-16
GE4:		MOV		AL,ES:[BX]
			OR		AL,AL
			JZ		GE5
			CALL	UPCASE
			MOV		[SI],AL
			INC		SI
			INC		BX
			LOOP	GE4
GE5:		MOV		AL,[SI-1]		; add '\' unless ends with : or \
			CMP		AL,':'
			JE		GE6
			CMP		AL,'\'
			JE		GE6
			MOV		BYTE PTR [SI],'\'
			INC		SI
GE6:		MOV		BYTE PTR [SI],0
			; skip to next string
GENX:		CMP		BYTE PTR ES:[DI],0
			JE		GENX1
			INC		DI
			JMP		GENX
GENX1:		INC		DI
			JMP		GE1
ENVKEY		DB		'ISISF'

; copy DOS command tail (if any) into LINE and flag one-shot mode
TAILCMD:
			MOV		ES,PSPSEG
			MOV		SI,81H
			XOR		CX,CX
			MOV		CL,ES:[80H]
			MOV		DI,OFFSET LINE
			XOR		BX,BX
TC1:		JCXZ	TC2
			MOV		AL,ES:[SI]
			INC		SI
			DEC		CX
			CMP		AL,CR
			JE		TC2
			CALL	UPCASE
			MOV		[DI],AL
			INC		DI
			CMP		AL,' '
			JE		TC1
			MOV		BX,1
			JMP		TC1
TC2:		MOV		BYTE PTR [DI],CR
			OR		BX,BX
			JZ		TC3
			MOV		ONESHOT,1
TC3:		RET

;-----------------------------------------------------------------------
; Console helpers (DS = CS)
;-----------------------------------------------------------------------
PUTS:		MOV		AH,9
			INT		21H
			RET
PUTC:		PUSH	AX				; DL = char
			PUSH	DX
			MOV		AH,2
			INT		21H
			POP		DX
			POP		AX
			RET
PCHR:		PUSH	DX				; AL = char
			MOV		DL,AL
			CALL	PUTC
			POP		DX
			RET
CRLF:		PUSH	AX
			MOV		AL,CR
			CALL	PCHR
			MOV		AL,LF
			CALL	PCHR
			POP		AX
			RET
SPACE:		PUSH	AX
			MOV		AL,' '
			CALL	PCHR
			POP		AX
			RET
PHEX4:		XCHG	AL,AH			; AX
			CALL	PHEX2
			XCHG	AL,AH
PHEX2:		PUSH	AX
			PUSH	CX
			MOV		CL,4
			PUSH	AX
			SHR		AL,CL
			CALL	PHEX1
			POP		AX
			CALL	PHEX1
			POP		CX
			POP		AX
			RET
PHEX1:		AND		AL,0FH
			ADD		AL,'0'
			CMP		AL,'9'
			JBE		PH1
			ADD		AL,7
PH1:		JMP		PCHR
PDEC:		PUSH	AX				; AX unsigned decimal
			PUSH	BX
			PUSH	CX
			PUSH	DX
			MOV		BX,10
			XOR		CX,CX
PD1:		XOR		DX,DX
			DIV		BX
			PUSH	DX
			INC		CX
			OR		AX,AX
			JNZ		PD1
PD2:		POP		AX
			ADD		AL,'0'
			CALL	PCHR
			LOOP	PD2
			POP		DX
			POP		CX
			POP		BX
			POP		AX
			RET
UPCASE:		CMP		AL,'a'
			JB		UC1
			CMP		AL,'z'
			JA		UC1
			SUB		AL,20H
UC1:		RET

; read a line from stdin into LINE (uppercase optional), CR-terminated.
; CX = length.  CF = end of input.  AL=1 -> uppercase
RDLINE:		MOV		RDUP,AL
			MOV		BRKFLG,0
			CMP		INDEV,0
			JE		RL5
			MOV		KBUF,126		; console: DOS buffered input (fn 0AH)
			MOV		DX,OFFSET KBUF
			MOV		AH,0AH
			INT		21H
			MOV		AL,LF			; fn 0AH echoes only the CR
			CALL	PCHR
			XOR		CX,CX
			MOV		CL,KBUF+1
			MOV		SI,OFFSET KBUF+2
			MOV		DI,OFFSET LINE
			PUSH	ES
			PUSH	DS
			POP		ES
			JCXZ	RL3
			; ^Z at start of line = end of input
			CMP		BYTE PTR [SI],1AH
			JNE		RL2
			POP		ES
			JMP		RLEOF
RL2:		REP		MOVSB
RL3:		POP		ES
			MOV		CL,KBUF+1
			JMP		RLFIN
RL5:		MOV		DI,OFFSET LINE	; redirected: byte at a time
			XOR		CX,CX
RL6:		PUSH	CX
			MOV		AH,3FH
			XOR		BX,BX
			MOV		CX,1
			MOV		DX,OFFSET RDCH
			INT		21H
			POP		CX
			JC		RL8
			OR		AX,AX
			JZ		RL8
			MOV		AL,RDCH
			CMP		AL,1AH
			JE		RL8
			CMP		AL,CR
			JE		RL6
			CMP		AL,LF
			JE		RL9
			CMP		CX,125
			JAE		RL6
			MOV		[DI],AL
			INC		DI
			INC		CX
			JMP		RL6
RL8:		JCXZ	RLEOF			; EOF
RL9:		PUSH	CX				; echo the line
			MOV		SI,OFFSET LINE
			JCXZ	RL11
RL10:		LODSB
			CALL	PCHR
			LOOP	RL10
RL11:		CALL	CRLF
			POP		CX
RLFIN:		MOV		SI,OFFSET LINE
			MOV		BX,CX
			MOV		BYTE PTR [SI+BX],CR
			CMP		RDUP,0
			JE		RLX
			JCXZ	RLX
			PUSH	CX
RL12:		MOV		AL,[SI]
			CALL	UPCASE
			MOV		[SI],AL
			INC		SI
			LOOP	RL12
			POP		CX
RLX:		CLC
			RET
RLEOF:		XOR		CX,CX
			MOV		LINE,CR
			STC
			RET

;-----------------------------------------------------------------------
; ISIS pathname parser.  ES:DI -> text.  Out: PDEV, PNAME(6), PEXT(3)
; (blank padded), PHASN=1 if a name was given, DI past the path,
; AX = 0 or ISIS error (4 illegal pathname, 5 bad device).
;-----------------------------------------------------------------------
PARSE:		MOV		AL,CURDRV
			MOV		PDEV,AL
			MOV		PHASN,0
			PUSH	DI
			MOV		DI,OFFSET PNAME
			PUSH	ES
			PUSH	DS
			POP		ES
			MOV		AL,' '
			MOV		CX,9
			REP		STOSB
			POP		ES
			POP		DI
PA0:		CMP		BYTE PTR ES:[DI],' '
			JNE		PA1
			INC		DI
			JMP		PA0
PA1:		CMP		BYTE PTR ES:[DI],':'
			JNE		PANAME
			CMP		BYTE PTR ES:[DI+3],':'
			JNE		PABDEV
			MOV		AL,ES:[DI+1]
			CALL	UPCASE
			MOV		AH,AL
			MOV		AL,ES:[DI+2]
			CALL	UPCASE
			ADD		DI,4
			CMP		AH,'F'
			JNE		PA2
			CMP		AL,'0'
			JB		PA2
			CMP		AL,'9'
			JA		PA2
			SUB		AL,'0'
			MOV		PDEV,AL
			JMP		SHORT PANAME
			; 2-char device names
PA2:		MOV		SI,OFFSET DEVNAM
			MOV		BL,10
PA3:		CMP		BYTE PTR [SI],0
			JE		PABDEV
			CMP		AH,[SI]
			JNE		PA4
			CMP		AL,[SI+1]
			JE		PA5
PA4:		ADD		SI,2
			INC		BL
			JMP		PA3
PA5:		MOV		PDEV,BL
PANAME:		MOV		SI,OFFSET PNAME
			MOV		CX,6
			CALL	PAFLD
			JC		PABAD
			CMP		BYTE PTR ES:[DI],'.'
			JNE		PA6
			INC		DI
			MOV		SI,OFFSET PEXT
			MOV		CX,3
			CALL	PAFLD
			JC		PABAD
PA6:		CMP		PDEV,10
			JB		PAOK
			CMP		PHASN,0			; device with a filename
			JNE		PABAD
PAOK:		XOR		AX,AX
			RET
PABAD:		MOV		AX,4
			RET
PABDEV:		MOV		AX,5
			RET
; copy up to CX alnum chars to [SI]; CF if too long
PAFLD:		MOV		AL,ES:[DI]
			CALL	UPCASE
			CMP		AL,'0'
			JB		PAF2
			CMP		AL,'9'
			JBE		PAF1
			CMP		AL,'A'
			JB		PAF2
			CMP		AL,'Z'
			JA		PAF2
PAF1:		JCXZ	PAF3
			MOV		[SI],AL
			INC		SI
			INC		DI
			DEC		CX
			MOV		PHASN,1
			JMP		PAFLD
PAF2:		CLC
			RET
PAF3:		STC
			RET

; ISIS device numbering 10..28 (SPATH)
DEVNAM		DB		'TITOVIVOI1O1TRHRR1R2TPHPP1P2LPL1BBCICO',0
; class per device 10..28: 0=CI 1=CO 2=AUXI 3=AUXO 4=PRN 5=BB
DEVCLS		DB		0,1,0,1,2,3,2,2,2,2,3,3,3,3,4,4,5,0,1

; build DOS path in PATHB from PDEV/PNAME/PEXT
MKPATH:		PUSH	ES
			PUSH	DS
			POP		ES
			MOV		DI,OFFSET PATHB
			MOV		AL,PDEV
			MOV		AH,PLEN-14
			MUL		AH
			ADD		AX,OFFSET DMAP
			MOV		SI,AX
MP1:		LODSB
			OR		AL,AL
			JZ		MP2
			STOSB
			JMP		MP1
MP2:		MOV		SI,OFFSET PNAME
			MOV		CX,6
MP3:		LODSB
			CMP		AL,' '
			JE		MP4
			STOSB
			LOOP	MP3
MP4:		CMP		PEXT,' '
			JE		MP6
			MOV		AL,'.'
			STOSB
			MOV		SI,OFFSET PEXT
			MOV		CX,3
MP5:		LODSB
			CMP		AL,' '
			JE		MP6
			STOSB
			LOOP	MP5
MP6:		XOR		AL,AL
			STOSB
			POP		ES
			RET

;-----------------------------------------------------------------------
; Command line interpreter
;-----------------------------------------------------------------------
CLI:		MOV		AX,CS
			MOV		DS,AX
			CLI
			MOV		AX,STK
			MOV		SS,AX
			MOV		SP,OFFSET STKTOP
			STI
			CALL	CLOSEALL
			CMP		ONESHOT,0
			JE		CLI1
			CMP		ONESHOT,2		; already ran the tail command
			JE		DOSEX
			MOV		ONESHOT,2
			CALL	CRLF
			JMP		SHORT CLI2
CLI1:		CALL	CRLF
			MOV		AL,CURDRV
			ADD		AL,'0'
			CALL	PCHR
			MOV		AL,'>'
			CALL	PCHR
			MOV		AL,1
			CALL	RDLINE
			JC		DOSEX
CLI2:		MOV		DI,OFFSET LINE
			PUSH	DS
			POP		ES
CL1:		CMP		BYTE PTR [DI],' '
			JNE		CL2
			INC		DI
			JMP		CL1
CL2:		CMP		BYTE PTR [DI],CR
			JE		CLI
			MOV		CMDPTR,DI
			; internal commands
			MOV		SI,OFFSET INTCMD
			XOR		BX,BX
CL3:		CMP		BYTE PTR [SI],0
			JNE		CL3A
			JMP		CLRUN
CL3A:
			PUSH	DI
			MOV		CX,4
CL4:		MOV		AL,[SI]
			CMP		AL,' '
			JE		CL5
			CMP		AL,[DI]
			JNE		CL6
			INC		SI
			INC		DI
			LOOP	CL4
CL5:		MOV		AL,[DI]			; must end the token
			CMP		AL,' '
			JE		CL7
			CMP		AL,CR
			JE		CL7
CL6:		POP		DI
			ADD		BX,2
			MOV		SI,BX
			ADD		SI,SI
			ADD		SI,OFFSET INTCMD
			JMP		CL3
CL7:		POP		AX
			JMP		WORD PTR CMDTAB[BX]
DOSEX:		CALL	CLOSEALL
			MOV		AX,4C00H
			INT		21H

INTCMD		DB		'DBUG','DIR ','ERA ','TYPE','REN ','EXIT',0
CMDTAB		DW		CMDDBUG,CMDDIR,CMDERA,CMDTYPE,CMDREN,DOSEX

COMERR:		MOV		SI,CMDPTR		; echo token + '?'
CE1:		LODSB
			CMP		AL,' '
			JE		CE2
			CMP		AL,CR
			JE		CE2
			CALL	PCHR
			JMP		CE1
CE2:		MOV		AL,'?'
			CALL	PCHR
			JMP		CLI

MSGNF		DB		CR,LF,'NOT FOUND$'
MSGRE		DB		CR,LF,'READ ERROR$'
MSGFE		DB		CR,LF,'FILE EXISTS$'
MSGALL		DB		CR,LF,'ALL FILES (Y/N)?$'
MSGTL		DB		CR,LF,'TRACE LEVEL: $'

; DBUG: set the ISIS-call trace level
CMDDBUG:
			MOV		DX,OFFSET MSGTL
			CALL	PUTS
			MOV		AL,1
			CALL	RDLINE
			MOV		AL,LINE
			SUB		AL,'0'
			CMP		AL,9
			JBE		DB1
			XOR		AL,AL
DB1:		MOV		TRLVL,AL
			JMP		CLI

; get optional path argument after the command word -> PDEV/PNAME/PEXT
; with '?' wildcards, build DOS search pattern in PATHB
ARGPAT:		MOV		SI,CMDPTR
AP1:		LODSB
			CMP		AL,' '
			JE		AP2
			CMP		AL,CR
			JNE		AP1
AP2:		DEC		SI
			MOV		DI,SI
			PUSH	DS
			POP		ES
			CALL	PARSEW
			RET
; parse allowing * and ? (DIR/ERA).  Uses PARSE then wildcard fixup.
PARSEW:		MOV		AL,CURDRV
			MOV		PDEV,AL
			PUSH	DI
			MOV		DI,OFFSET PNAME
			MOV		AL,' '
			MOV		CX,9
			REP		STOSB
			POP		DI
PW0:		CMP		BYTE PTR [DI],' '
			JNE		PW1
			INC		DI
			JMP		PW0
PW1:		CMP		BYTE PTR [DI],':'
			JNE		PW3
			MOV		AL,[DI+2]
			SUB		AL,'0'
			CMP		AL,9
			JA		PWBAD
			CMP		BYTE PTR [DI+1],'F'
			JNE		PWBAD
			CMP		BYTE PTR [DI+3],':'
			JNE		PWBAD
			MOV		PDEV,AL
			ADD		DI,4
PW3:		MOV		SI,OFFSET PNAME
			MOV		CX,6
			CALL	PWFLD
			CMP		BYTE PTR [DI],'.'
			JNE		PW4
			INC		DI
			MOV		SI,OFFSET PEXT
			MOV		CX,3
			CALL	PWFLD
			JMP		SHORT PW5
PW4:		CMP		PNAME,' '		; no name and no ext: all
			JNE		PW5
			MOV		PNAME,'*'
			MOV		PEXT,'*'
PW5:		CMP		PNAME,' '		; ".EXT" only -> *.EXT
			JNE		PW6
			MOV		PNAME,'*'
PW6:		CALL	MKPATH
			CMP		PEXT,' '		; no extension: search NAME. explicitly
			JNE		PW7
			MOV		DI,OFFSET PATHB
PW8:		CMP		BYTE PTR [DI],0
			JE		PW9
			INC		DI
			JMP		PW8
PW9:		MOV		BYTE PTR [DI],'.'
			MOV		BYTE PTR [DI+1],0
PW7:		XOR		AX,AX
			RET
PWBAD:		MOV		AX,4
			RET
PWFLD:		MOV		AL,[DI]
			CMP		AL,'*'
			JE		PWF1
			CMP		AL,'?'
			JE		PWF1
			CMP		AL,'0'
			JB		PWF2
			CMP		AL,'9'
			JBE		PWF1
			CMP		AL,'A'
			JB		PWF2
			CMP		AL,'Z'
			JA		PWF2
PWF1:		JCXZ	PWF3
			MOV		[SI],AL
			INC		SI
			DEC		CX
PWF3:		INC		DI
			JMP		PWFLD
PWF2:		RET

; DIR [:Fn:][pattern]   -- 4 entries per line like ISX
CMDDIR:		CALL	ARGPAT
			OR		AX,AX
			JZ		DR0
			JMP		COMERR
DR0:		CALL	SETDTA
			MOV		DX,OFFSET PATHB
			MOV		CX,0			; normal files
			MOV		AH,4EH
			INT		21H
			JNC		DR1
			MOV		DX,OFFSET MSGNF
			CALL	PUTS
			JMP		CLI
DR1:		XOR		BX,BX			; entry counter
DR2:		TEST	BL,3
			JNZ		DR3
			CALL	CRLF
			MOV		AL,'F'
			CALL	PCHR
			MOV		AL,PDEV
			ADD		AL,'0'
			CALL	PCHR
			MOV		AL,':'
			CALL	PCHR
			JMP		SHORT DR4
DR3:		CALL	SPACE
			MOV		AL,':'
			CALL	PCHR
DR4:		CALL	SPACE
			; name.ext
			MOV		SI,OFFSET DTA+30
			MOV		CX,8
DR5:		MOV		AL,[SI]
			CMP		AL,'.'
			JE		DR6
			OR		AL,AL
			JE		DR6
			CALL	PCHR
			INC		SI
			LOOP	DR5
DR6:		JCXZ	DR7
			CALL	SPACE
			LOOP	DR6
DR7:		CALL	SPACE
			MOV		CX,3
			CMP		BYTE PTR [SI],'.'
			JNE		DR9
			INC		SI
DR8:		MOV		AL,[SI]
			OR		AL,AL
			JE		DR9
			CALL	PCHR
			INC		SI
			LOOP	DR8
DR9:		MOV		AL,BL			; pad ext unless last column
			AND		AL,3
			CMP		AL,3
			JE		DR11
			JCXZ	DR11
DR10:		CALL	SPACE
			LOOP	DR10
DR11:		INC		BX
			MOV		AH,4FH
			INT		21H
			JNC		DR2
			JMP		CLI

SETDTA:		MOV		DX,OFFSET DTA
			MOV		AH,1AH
			INT		21H
			RET

; ERA [:Fn:]pattern
CMDERA:		CALL	ARGPAT
			OR		AX,AX
			JZ		ER0
			JMP		COMERR
ER0:		MOV		SI,CMDPTR		; any argument at all?
ER1:		LODSB
			CMP		AL,' '
			JE		ER2
			CMP		AL,CR
			JNE		ER1
			JMP		COMERR
ER2:		CMP		PNAME,'*'
			JNE		ER4
			CMP		PEXT,'*'
			JNE		ER4
			MOV		DX,OFFSET MSGALL
			CALL	PUTS
			MOV		AL,1
			CALL	RDLINE
			CMP		LINE,'Y'
			JE		ER4
			JMP		CLI
ER4:		CALL	SETDTA
			MOV		DX,OFFSET PATHB
			XOR		CX,CX
			MOV		AH,4EH
			INT		21H
			JNC		ER5
			MOV		DX,OFFSET MSGNF
			CALL	PUTS
			JMP		CLI
ER5:		CALL	DIRPFX			; prefix dir + found name
			MOV		DX,OFFSET PATH2
			MOV		AH,41H
			INT		21H
			MOV		AH,4FH
			INT		21H
			JNC		ER5
			JMP		CLI

; PATH2 = directory part of PATHB + DTA name
DIRPFX:		PUSH	ES
			PUSH	DS
			POP		ES
			MOV		SI,OFFSET PATHB
			MOV		BX,SI
DP1:		LODSB					; find last ':' or '\'
			OR		AL,AL
			JZ		DP2
			CMP		AL,':'
			JE		DP1A
			CMP		AL,'\'
			JNE		DP1
DP1A:		MOV		BX,SI
			JMP		DP1
DP2:		MOV		CX,BX
			SUB		CX,OFFSET PATHB
			MOV		SI,OFFSET PATHB
			MOV		DI,OFFSET PATH2
			REP		MOVSB
			MOV		SI,OFFSET DTA+30
DP3:		LODSB
			STOSB
			OR		AL,AL
			JNZ		DP3
			POP		ES
			RET

; TYPE file
CMDTYPE:
			CALL	ARGPAT
			OR		AX,AX
			JZ		TY0
			JMP		COMERR
TY0:		MOV		DX,OFFSET PATHB
			MOV		AX,3D00H
			INT		21H
			JNC		TY1
			MOV		DX,OFFSET MSGNF
			CALL	PUTS
			JMP		CLI
TY1:		MOV		BX,AX
			CALL	CRLF
TY2:		MOV		DX,OFFSET LDBUF
			MOV		CX,512
			MOV		AH,3FH
			INT		21H
			JC		TY5
			OR		AX,AX
			JZ		TY5
			MOV		CX,AX
			MOV		SI,OFFSET LDBUF
TY3:		LODSB
			CMP		AL,1AH
			JE		TY5
			CALL	PCHR
			CMP		BRKFLG,0
			JNE		TY5
			LOOP	TY3
			JMP		TY2
TY5:		MOV		AH,3EH
			INT		21H
			MOV		BRKFLG,0
			JMP		CLI

; REN new=old
CMDREN:		MOV		SI,CMDPTR
RN1:		LODSB
			CMP		AL,' '
			JE		RN2
			CMP		AL,CR
			JNE		RN1
			JMP		COMERR
RN2:		DEC		SI
			MOV		DI,SI
			PUSH	DS
			POP		ES
			CALL	PARSE
			OR		AX,AX
			JNZ		RNBAD
			CMP		PHASN,0
			JE		RNBAD
			CMP		PDEV,10
			JAE		RNBAD
			CMP		BYTE PTR [DI],'='
			JNE		RNBAD
			INC		DI
			PUSH	DI
			CALL	MKPATH			; new -> PATH2
			MOV		SI,OFFSET PATHB
			MOV		DI,OFFSET PATH2
			MOV		CX,PLEN
			REP		MOVSB
			POP		DI
			CALL	PARSE
			OR		AX,AX
			JNZ		RNBAD
			CMP		PHASN,0
			JE		RNBAD
			CALL	MKPATH			; old -> PATHB
			MOV		DX,OFFSET PATH2	; new exists?
			MOV		AX,4300H
			INT		21H
			JC		RN3
			MOV		DX,OFFSET MSGFE
			CALL	PUTS
			JMP		CLI
RN3:		MOV		DX,OFFSET PATHB
			MOV		DI,OFFSET PATH2
			MOV		AH,56H
			INT		21H
			JNC		RN4
			MOV		DX,OFFSET MSGNF
			CALL	PUTS
RN4:		JMP		CLI
RNBAD:		JMP		COMERR

;-----------------------------------------------------------------------
; Run a program:  CMDPTR -> "[:Fn:]NAME[.EXT] tail"
;-----------------------------------------------------------------------
CLRUN:		MOV		DI,CMDPTR
			PUSH	DS
			POP		ES
			CALL	PARSE
			OR		AX,AX
			JNZ		RU1
			CMP		PDEV,10
			JAE		RU1
			CMP		PHASN,0
			JNE		RU2
			; bare ":Fn:" -> change drive
			CMP		BYTE PTR [DI],' '
			JE		RU0
			CMP		BYTE PTR [DI],CR
			JNE		RU1
RU0:		MOV		AL,PDEV
			MOV		CURDRV,AL
			JMP		CLI
RU1:		JMP		COMERR
RU2:		CALL	MKPATH
			MOV		DX,OFFSET PATHB
			MOV		AX,3D00H
			INT		21H
			JC		RU1
			MOV		LDHAND,AX
			MOV		LDBIAS,0
			CALL	LOADER
			PUSH	AX
			MOV		BX,LDHAND
			MOV		AH,3EH
			INT		21H
			POP		AX
			OR		AX,AX
			JNZ		RU1
			; :CI: buffer = whole command line, positioned after command name
			MOV		SI,CMDPTR
			MOV		DI,OFFSET CIBUF
			PUSH	DS
			POP		ES
			XOR		CX,CX
RU3:		LODSB
			STOSB
			INC		CX
			CMP		AL,CR
			JNE		RU3
			MOV		AL,LF
			STOSB
			INC		CX
			MOV		CILEN,CX
			XOR		BX,BX
RU4:		MOV		AL,CIBUF[BX]
			CMP		AL,' '
			JE		RU5
			CMP		AL,CR
			JE		RU5
			INC		BX
			JMP		RU4
RU5:		MOV		CIIDX,BX
			CALL	CRLF
			CALL	INITSLOT
			MOV		AX,LDENT
			OR		AX,AX
			JNZ		RU6
			MOV		AX,LDLOWA
RU6:		MOV		R_SI,AX			; PC
			MOV		ES,MEMSEG
			MOV		R_BP,STK80-2	; SP, return -> 0000 (exit trap)
			MOV		WORD PTR ES:[STK80-2],0
			CALL	INSTRAP
			XOR		AX,AX
			MOV		R_AX,AX
			MOV		R_BX,AX
			MOV		R_CX,AX
			MOV		R_DX,AX
			JMP		RESUME

;-----------------------------------------------------------------------
; Absolute OMF-80 loader.  LDHAND = DOS handle, LDBIAS = bias.
; Out: AX = 0 ok, 15 (bad address) or 16 (bad format); LDENT, LDLOWA.
;-----------------------------------------------------------------------
LOADER:		MOV		LDENT,0
			MOV		LDLOWA,0
			MOV		LDCNT,0
			MOV		LDPTR,0
			MOV		LDANY,0
			MOV		ES,MEMSEG
LR1:		MOV		LDSUM,0
			CALL	LDGETB
			JC		LRBAD
			MOV		LDTYP,AL
			CALL	LDGETB
			JC		LRBAD
			MOV		AH,AL
			CALL	LDGETB
			JC		LRBAD
			XCHG	AL,AH
			OR		AX,AX
			JZ		LRBAD
			DEC		AX				; content length (without checksum)
			MOV		LDREM,AX
			CMP		LDTYP,6
			JE		LRCONT
			CMP		LDTYP,4
			JE		LREND
LRSKIP:		CALL	LDSKIP			; rest + checksum
			JC		LRBAD
			CMP		LDTYP,0EH
			JNE		LR1
			CMP		LDANY,0
			JE		LRBAD
			XOR		AX,AX
			RET
LRBAD:		MOV		AX,16
			RET
LRADR:		MOV		AX,15
			RET
LREND:		CMP		LDREM,4
			JB		LRSKIP
			CALL	LDGETB			; module type
			MOV		CL,AL			; (LDGETB clobbers BX)
			CALL	LDGETB			; segment
			CALL	LDGETB
			MOV		DL,AL
			CALL	LDGETB
			MOV		DH,AL
			SUB		LDREM,4
			CMP		CL,1
			JNE		LRSKIP
			MOV		LDENT,DX
			JMP		LRSKIP
LRCONT:		CMP		LDREM,3
			JB		LRBAD
			CALL	LDGETB			; segment must be 0 (absolute)
			OR		AL,AL
			JNZ		LRBAD
			CALL	LDGETB
			MOV		DL,AL
			CALL	LDGETB
			MOV		DH,AL
			SUB		LDREM,3
			ADD		DX,LDBIAS
			CMP		DX,LDLOW
			JB		LRADR
			MOV		AX,DX			; end = addr + n must be <= MEMTOP+1
			ADD		AX,LDREM
			JC		LRADR
			CMP		AX,MEMTOP+1
			JA		LRADR
			CMP		LDANY,0
			JE		LRC1
			CMP		DX,LDLOWA
			JAE		LRC2
LRC1:		MOV		LDLOWA,DX
LRC2:		MOV		LDANY,1
			MOV		DI,DX
LRC3:		CMP		LDREM,0
			JE		LRC4
			CALL	LDGETB
			JNC		LRC3A
			JMP		LRBAD
LRC3A:		STOSB
			DEC		LDREM
			JMP		LRC3
LRC4:		CALL	LDSKIP			; checksum
			JNC		LRC4A
			JMP		LRBAD
LRC4A:
			JMP		LR1
; skip LDREM bytes + checksum; CF if EOF or checksum error
LDSKIP:		CMP		LDREM,0
			JE		LS1
			CALL	LDGETB
			JC		LS2
			DEC		LDREM
			JMP		LDSKIP
LS1:		CALL	LDGETB
			JC		LS2
			CMP		LDSUM,0
			JNE		LS3
			CLC
LS2:		RET
LS3:		STC
			RET
; next byte of the load file -> AL, CF at EOF.  Sums into LDSUM.
LDGETB:		MOV		BX,LDPTR
			CMP		BX,LDCNT
			JB		LG1
			PUSH	CX
			PUSH	DX
			MOV		BX,LDHAND
			MOV		CX,512
			MOV		DX,OFFSET LDBUF
			MOV		AH,3FH
			INT		21H
			POP		DX
			POP		CX
			JC		LG2
			OR		AX,AX
			JZ		LG2
			MOV		LDCNT,AX
			XOR		BX,BX
LG1:		MOV		AL,LDBUF[BX]
			INC		BX
			MOV		LDPTR,BX
			ADD		LDSUM,AL
			CLC
			RET
LG2:		STC
			RET

;-----------------------------------------------------------------------
; AFTN slot table
;-----------------------------------------------------------------------
INITSLOT:
			MOV		BX,0
IS1:		MOV		STYPE[BX],ST_FREE
			INC		BX
			CMP		BX,NSLOT
			JB		IS1
			MOV		STYPE,ST_CO
			MOV		SACC,2
			MOV		STYPE+1,ST_CI
			MOV		SACC+1,1
			RET
CLOSEALL:
			MOV		BX,2
CA1:		CALL	CLOSESL
			INC		BX
			CMP		BX,NSLOT
			JB		CA1
			RET
CLOSESL:							; BX = slot
			CMP		STYPE[BX],ST_DISK
			JNE		CS1
			PUSH	BX
			SHL		BX,1
			MOV		BX,SHAND[BX]
			MOV		AH,3EH
			INT		21H
			POP		BX
CS1:		MOV		STYPE[BX],ST_FREE
			RET
; find a free slot >= 2 -> BX, CF if none
FREESL:		MOV		BX,2
FS1:		CMP		STYPE[BX],ST_FREE
			JE		FS2
			INC		BX
			CMP		BX,NSLOT
			JB		FS1
			STC
			RET
FS2:		CLC
			RET
; SI -> slot path (BX = slot)
SLPATH:		MOV		AX,BX
			MOV		CL,PLEN
			MUL		CL
			ADD		AX,OFFSET SPATHS
			MOV		SI,AX
			RET
; is PATHB open in some disk slot? ZF=1 -> yes (BX = slot)
ISOPEN:		MOV		BX,2
IO1:		CMP		STYPE[BX],ST_DISK
			JNE		IO3
			CALL	SLPATH
			MOV		DI,OFFSET PATHB
			PUSH	ES
			PUSH	DS
			POP		ES
IO2:		MOV		AL,[SI]
			CMP		AL,[DI]
			JNE		IO2X
			INC		SI
			INC		DI
			OR		AL,AL
			JNZ		IO2
			POP		ES
			RET						; ZF=1
IO2X:		POP		ES
IO3:		INC		BX
			CMP		BX,NSLOT
			JB		IO1
			OR		BX,BX			; ZF=0
			RET

;-----------------------------------------------------------------------
; Interpreter entry/exit
;-----------------------------------------------------------------------
RESUME:		MOV		AX,R_AX
			MOV		BX,R_BX
			MOV		CX,R_CX
			MOV		DX,R_DX
			MOV		SI,R_SI
			MOV		BP,R_BP
			MOV		ES,MEMSEG
			MOV		DS,MEMSEG
			NXT

OP_HLT:		DEC		SI
			CALL	SAVREG
			MOV		DX,OFFSET MSGHLT
			JMP		SHORT ABTPC
OP_TRAP:
			MOV		DI,WORD PTR [SI]
			INC		SI
			AND		DI,0FFH
			CALL	SAVREG
			CMP		DI,TR_BRK
			JBE		TP1
			MOV		DI,TR_BRK
TP1:		SHL		DI,1
			JMP		WORD PTR TRAPTAB[DI]
SAVREG:		MOV		CS:R_AX,AX
			MOV		CS:R_BX,BX
			MOV		CS:R_CX,CX
			MOV		CS:R_DX,DX
			MOV		CS:R_SI,SI
			MOV		CS:R_BP,BP
			MOV		AX,CS
			MOV		DS,AX
			MOV		ES,MEMSEG
			RET
MSGHLT		DB		CR,LF,'HALT AT $'
MSGBRK		DB		CR,LF,'BREAK AT $'
; print message DX + PC (R_SI-1) and abort to CLI
ABTPC:		CALL	PUTS
			MOV		AX,R_SI
			DEC		AX
			DEC		AX
			CALL	PHEX4
			JMP		CLI

TRAPTAB		DW		TRISIS,MONERR,MONCI,MONERR,MONCO,MONPO,MONLO,MONCST
			DW		MONIOC,MONIOS,MONMEM,MONERR,MONERR,TREXIT,TRBRK

TRBRK:		MOV		DX,OFFSET MSGBRK
			JMP		ABTPC
TREXIT:		JMP		CLI

; Intellec monitor entries (F800H..)
MONCI:		MOV		AH,8			; console in, no echo
			INT		21H
			MOV		BYTE PTR R_AX,AL
			JMP		MONRET
MONCO:		MOV		DL,BYTE PTR R_CX
			CALL	PUTC
			JMP		MONRET
MONPO:		MOV		DL,BYTE PTR R_CX
			MOV		AH,4
			INT		21H
			JMP		MONRET
MONLO:		MOV		DL,BYTE PTR R_CX
			MOV		AH,5
			INT		21H
			JMP		MONRET
MONCST:		MOV		AH,0BH
			INT		21H
			MOV		BYTE PTR R_AX,AL
			JMP		MONRET
MONIOC:		MOV		AL,IOBYTE		; IOCHK: A = I/O byte
			MOV		BYTE PTR R_AX,AL
			JMP		MONRET
			; IOSET: I/O byte = C
MONIOS:		MOV		AL,BYTE PTR R_CX
			MOV		IOBYTE,AL
			JMP		MONRET
			; MEMCK: BA = top
MONMEM:		MOV		BYTE PTR R_AX,LOW MEMTOP
			MOV		BYTE PTR R_CX+1,HIGH MEMTOP
			JMP		MONRET
MONERR:		MOV		AX,255
			CALL	ERRRPT
MONRET:		CMP		BRKFLG,0
			JE		MR1
			JMP		BRKABT
MR1:		JMP		RESUME

BRKABT:		MOV		BRKFLG,0
			MOV		DX,OFFSET MSGCC
			CALL	PUTS
			JMP		CLI
MSGCC		DB		'^C$'

; "ERROR nnn, AT USER PC xxxx" -- PC = return address on the 8080 stack
ERRRPT:		PUSH	AX
			MOV		DX,OFFSET MSGERR
			CALL	PUTS
			POP		AX
			CALL	PDEC
			MOV		DX,OFFSET MSGAT
			CALL	PUTS
			MOV		BX,R_BP
			MOV		AX,ES:[BX]
			CALL	PHEX4
			CALL	CRLF
			RET
MSGERR		DB		CR,LF,'ERROR $'
MSGAT		DB		', AT USER PC $'

;-----------------------------------------------------------------------
; ISIS system call:  C = function, DE -> parameter block
;-----------------------------------------------------------------------
TRISIS:		MOV		AX,R_DX
			MOV		PBLK,AX
			MOV		BL,BYTE PTR R_CX
			XOR		BH,BH
			CMP		TRLVL,0
			JE		TI1
			CALL	TRACE
TI1:		CMP		BX,15
			JB		TI2
			MOV		AX,18
			CALL	ERRRPT
			JMP		ISRET
TI2:		SHL		BX,1
			JMP		WORD PTR ISTAB[BX]
ISTAB		DW		FOPEN,FCLOSE,FDEL,FREAD,FWRITE,FSEEK,FLOAD,FRENAM
			DW		FCONS,FEXIT,FATTR,FRESC,FERROR,FWHO,FSPATH

ISRET:		CMP		BRKFLG,0
			JE		IR1
			JMP		BRKABT
IR1:		JMP		RESUME

; next parameter word -> AX
GETARG:		PUSH	BX
			MOV		BX,PBLK
			MOV		AX,ES:[BX]
			ADD		PBLK,2
			POP		BX
			RET
; store AX through the next parameter (a pointer), then return to 8080
SETST:		PUSH	AX
			CALL	GETARG
			MOV		BX,AX
			POP		AX
			MOV		ES:[BX],AX
			JMP		ISRET
; store AX at 8080 address in DI
PUTW:		MOV		ES:[DI],AX
			RET

TRACE:		PUSH	BX				; name + parameter words
			CALL	CRLF
			MOV		AX,BX
			CMP		AX,15
			JB		TR1
			MOV		AX,15
TR1:		MOV		CL,3
			SHL		AX,CL
			ADD		AX,OFFSET FNAMES
			MOV		SI,AX
			MOV		CX,8
TR2:		LODSB
			CALL	PCHR
			LOOP	TR2
			MOV		BX,PBLK
			MOV		CX,5
TR3:		CALL	SPACE
			MOV		AX,ES:[BX]
			CALL	PHEX4
			ADD		BX,2
			LOOP	TR3
			POP		BX
			RET
FNAMES		DB		'OPEN    CLOSE   DELETE  READ    WRITE   SEEK    '
			DB		'LOAD    RENAME  CONSOLE EXIT    ATTRIB  RESCAN  '
			DB		'ERROR   WHOCON  SPATH   ???     '

; parse the path whose 8080 address is the next argument
PARG:		CALL	GETARG
			MOV		DI,AX
			CALL	PARSE
			RET

;--- OPEN (AFTN$P, PATH$P, ACCESS, ECHO, STATUS$P)
FOPEN:		CALL	GETARG
			MOV		OPAFTP,AX
			CALL	PARG
			MOV		OPERR,AX
			CALL	GETARG
			MOV		OPACC,AX
			CALL	GETARG
			MOV		OPECHO,AX
			MOV		AX,OPACC
			CMP		AX,1
			JB		OPE22
			CMP		AX,3
			JA		OPE22
			MOV		AX,OPERR
			OR		AX,AX
			JZ		OP1
			JMP		OPEX
OPE22:		MOV		AX,22
			JMP		OPEX
OP1:		CMP		PDEV,10
			JB		OPDISK
			MOV		BL,PDEV			; device
			SUB		BL,10
			XOR		BH,BH
			MOV		AL,DEVCLS[BX]
			OR		AL,AL
			JNZ		OP2
			MOV		AX,1			; console input -> AFTN 1
			JMP		OPAFT
OP2:		CMP		AL,1
			JNE		OP3
			XOR		AX,AX			; console output -> AFTN 0
			JMP		OPAFT
OP3:		MOV		CL,AL
			CALL	FREESL
			JNC		OP4
			MOV		AX,3
			JMP		OPEX
OP4:		MOV		AL,ST_AUXI
			CMP		CL,2
			JE		OP5
			MOV		AL,ST_AUXO
			CMP		CL,3
			JE		OP5
			MOV		AL,ST_PRN
			CMP		CL,4
			JE		OP5
			MOV		AL,ST_BB
OP5:		MOV		STYPE[BX],AL
			MOV		AL,BYTE PTR OPACC
			MOV		SACC[BX],AL
			MOV		AX,BX
			JMP		OPAFT
OPDISK:		CMP		PHASN,0
			JNE		OD1
			MOV		AX,23
			JMP		OPEX
OD1:		CALL	MKPATH
			CALL	ISOPEN
			JNZ		OD2
			MOV		AX,12
			JMP		OPEX
OD2:		CALL	FREESL
			JNC		OD3
			MOV		AX,3
			JMP		OPEX
OD3:		MOV		OPSLOT,BX
			MOV		DX,OFFSET PATHB
			MOV		AX,OPACC
			CMP		AX,1
			JNE		OD4
			MOV		AX,3D00H		; read
			INT		21H
			JNC		OD7
			MOV		AX,13
			JMP		OPEX
OD4:		CMP		AX,2
			JE		OD5
			MOV		AX,3D02H		; update: open or create
			INT		21H
			JNC		OD7
OD5:		XOR		CX,CX			; write: create/truncate
			MOV		AH,3CH
			INT		21H
			JNC		OD7
			MOV		AX,9
			JMP		OPEX
OD7:		MOV		BX,OPSLOT
			MOV		STYPE[BX],ST_DISK
			MOV		CL,BYTE PTR OPACC
			MOV		SACC[BX],CL
			MOV		DI,BX
			SHL		DI,1
			MOV		SHAND[DI],AX
			CALL	SLPATH			; remember the path
			MOV		DI,SI
			MOV		SI,OFFSET PATHB
			PUSH	ES
			PUSH	DS
			POP		ES
			MOV		CX,PLEN
			REP		MOVSB
			POP		ES
			MOV		AX,BX
OPAFT:		MOV		DI,OPAFTP		; return AFTN
			CALL	PUTW
			MOV		BX,AX			; echo file check (read access only)
			MOV		AX,OPECHO
			OR		AX,AX
			JZ		OPOK
			CMP		OPACC,1
			JNE		OPE25
			CMP		AX,NSLOT
			JAE		OPE25
			MOV		BX,AX
			CMP		STYPE[BX],ST_FREE
			JE		OPE25
			CMP		SACC[BX],1
			JE		OPE25
OPOK:		XOR		AX,AX
			JMP		SHORT OPEX
OPE25:		MOV		AX,25
OPEX:		JMP		SETST

;--- CLOSE (AFTN, STATUS$P)
FCLOSE:		CALL	GETARG
			CMP		AX,NSLOT
			JB		FC1
			MOV		AX,2
			JMP		SETST
FC1:		CMP		AX,2
			JB		FC2
			MOV		BX,AX
			CALL	CLOSESL
FC2:		XOR		AX,AX
			JMP		SETST

;--- DELETE (PATH$P, STATUS$P)
FDEL:		CALL	PARG
			OR		AX,AX
			JNZ		FD9
			MOV		AX,17
			CMP		PDEV,10
			JAE		FD9
			MOV		AX,23
			CMP		PHASN,0
			JE		FD9
			CALL	MKPATH
			CALL	ISOPEN
			MOV		AX,32
			JZ		FD9
			MOV		DX,OFFSET PATHB
			MOV		AH,41H
			INT		21H
			XOR		AX,AX			; as ISX: always "no error"
FD9:		JMP		SETST

; slot from AFTN argument -> BX; CF if not open
GETSLOT:
			CALL	GETARG
			CMP		AX,NSLOT
			JAE		GS1
			MOV		BX,AX
			CMP		STYPE[BX],ST_FREE
			JE		GS1
			CLC
			RET
GS1:		STC
			RET

;--- READ (AFTN, BUFFER$P, COUNT, ACTUAL$P, STATUS$P)
FREAD:		CALL	GETSLOT
			PUSHF
			CALL	GETARG
			MOV		RWBUF,AX
			CALL	GETARG
			MOV		RWCNT,AX
			CALL	GETARG
			MOV		RWACTP,AX
			MOV		RWACT,0
			POPF
			JNC		FR1
			MOV		AX,2
			JMP		FRX
FR1:		MOV		AL,STYPE[BX]
			CMP		AL,ST_CI
			JE		FRCI
			CMP		AL,ST_BB
			JNE		FR2
			JMP		FROK
FR2:		CMP		SACC[BX],2
			JNE		FR3
			MOV		AX,8
			JMP		FRX
FR3:		CMP		AL,ST_DISK
			JE		FR4
			CMP		AL,ST_AUXI
			JE		FR5
			MOV		AX,8
			JMP		FRX
FR4:		SHL		BX,1
			MOV		BX,SHAND[BX]
			JMP		SHORT FR6
FR5:		MOV		BX,3
FR6:		CALL	CLAMP
			PUSH	DS
			MOV		DX,RWBUF
			MOV		DS,MEMSEG
			MOV		AH,3FH
			INT		21H
			POP		DS
			JC		FRIOE
			MOV		RWACT,AX
			JMP		FROK
FRIOE:		MOV		AX,24
			JMP		SHORT FRX
FRCI:		MOV		AX,CIIDX		; :CI: line buffer
			CMP		AX,CILEN
			JB		FC3
			XOR		AL,AL			; need a new line
			CALL	RDLINE
			JNC		FCI1
			MOV		CILEN,0			; end of input: 0 bytes
			MOV		CIIDX,0
			JMP		SHORT FROK
FCI1:		MOV		SI,OFFSET LINE
			MOV		DI,OFFSET CIBUF
			PUSH	ES
			PUSH	DS
			POP		ES
			INC		CX
			MOV		BX,CX
			REP		MOVSB			; text + CR
			POP		ES
			MOV		CIBUF[BX],LF
			INC		BX
			MOV		CILEN,BX
			MOV		CIIDX,0
FC3:		MOV		CX,CILEN
			SUB		CX,CIIDX
			CMP		CX,RWCNT
			JBE		FC4
			MOV		CX,RWCNT
FC4:		MOV		RWACT,CX
			MOV		SI,OFFSET CIBUF
			ADD		SI,CIIDX
			ADD		CIIDX,CX
			MOV		DI,RWBUF
			REP		MOVSB			; DS:SI -> ES:DI (8080 memory)
FROK:		XOR		AX,AX
FRX:		PUSH	AX
			MOV		AX,RWACT
			MOV		DI,RWACTP
			CALL	PUTW
			POP		AX
			JMP		SETST

; limit CX = RWCNT so buffer does not run past 64K
CLAMP:		MOV		CX,RWCNT
			MOV		AX,RWBUF
			ADD		AX,CX
			JNC		CL9
			MOV		CX,RWBUF
			NEG		CX
CL9:		RET

;--- WRITE (AFTN, BUFFER$P, COUNT, STATUS$P)
FWRITE:		CALL	GETSLOT
			PUSHF
			CALL	GETARG
			MOV		RWBUF,AX
			CALL	GETARG
			MOV		RWCNT,AX
			POPF
			JNC		FW1
			MOV		AX,2
			JMP		SETST
FW1:		MOV		AL,STYPE[BX]
			CMP		AL,ST_BB
			JNE		FW2
			JMP		FWOK
FW2:		CMP		SACC[BX],1
			JE		FWE6
			CMP		AL,ST_CO
			JNE		FW3
			MOV		BX,1
			JMP		SHORT FW7
FW3:		CMP		AL,ST_PRN
			JNE		FW4
			MOV		BX,4
			JMP		SHORT FW7
FW4:		CMP		AL,ST_AUXO
			JNE		FW5
			MOV		BX,3
			JMP		SHORT FW7
FW5:		CMP		AL,ST_DISK
			JE		FW6
FWE6:		MOV		AX,6
			JMP		SETST
FW6:		SHL		BX,1
			MOV		BX,SHAND[BX]
FW7:		CALL	CLAMP
			JCXZ	FWOK
			PUSH	CX
			PUSH	DS
			MOV		DX,RWBUF
			MOV		DS,MEMSEG
			MOV		AH,40H
			INT		21H
			POP		DS
			POP		CX
			JC		FWE7
			CMP		AX,CX
			JB		FWE7
FWOK:		XOR		AX,AX
			JMP		SETST
FWE7:		MOV		AX,7
			JMP		SETST

;--- SEEK (AFTN, MODE, BLOCK$P, BYTE$P, STATUS$P)
FSEEK:		CALL	GETSLOT
			PUSHF
			CALL	GETARG
			MOV		SKMODE,AX
			CALL	GETARG
			MOV		SKBLKP,AX
			CALL	GETARG
			MOV		SKBYTP,AX
			POPF
			JNC		SK1
			MOV		AX,2
			JMP		SETST
SK1:		CMP		STYPE[BX],ST_DISK
			JE		SK2
			MOV		AX,19
			JMP		SETST
SK2:		MOV		AL,SACC[BX]
			MOV		SKACC,AL
			CMP		AL,2
			JNE		SK3
			MOV		AX,31
			JMP		SETST
SK3:		SHL		BX,1
			MOV		BX,SHAND[BX]
			MOV		SKHAND,BX
			MOV		AX,4201H		; current position -> SKCUR
			XOR		CX,CX
			XOR		DX,DX
			INT		21H
			MOV		SKCURL,AX
			MOV		SKCURH,DX
			MOV		AX,4202H		; size -> SKSIZ
			XOR		CX,CX
			XOR		DX,DX
			INT		21H
			MOV		SKSIZL,AX
			MOV		SKSIZH,DX
			MOV		SKST,0
			MOV		AX,SKMODE
			OR		AX,AX
			JNZ		SK5
			MOV		AX,SKCURL		; mode 0: report position
			MOV		DX,SKCURH
			MOV		BX,AX
			AND		BX,7FH
			MOV		CX,7
SK4:		SHR		DX,1
			RCR		AX,1
			LOOP	SK4
			MOV		DI,SKBLKP
			CALL	PUTW
			MOV		AX,BX
			MOV		DI,SKBYTP
			CALL	PUTW
			MOV		AX,SKCURL
			MOV		DX,SKCURH
			JMP		SKSET
SK5:		CMP		AX,4
			JNE		SK6
			MOV		AX,SKSIZL		; mode 4: end of file
			MOV		DX,SKSIZH
			JMP		SKSET
SK6:		CMP		AX,3
			JBE		SK7
			MOV		AX,27
			JMP		SKRST
SK7:		MOV		BX,SKBLKP		; offset = block*128 + byte
			MOV		AX,ES:[BX]
			XOR		DX,DX
			MOV		CX,7
SK8:		SHL		AX,1
			RCL		DX,1
			LOOP	SK8
			MOV		BX,SKBYTP
			ADD		AX,ES:[BX]
			ADC		DX,0
			CMP		SKMODE,2
			JE		SKCHK
			CMP		SKMODE,3
			JNE		SKBACK
			ADD		AX,SKCURL		; forward
			ADC		DX,SKCURH
			JMP		SHORT SKCHK
SKBACK:		MOV		CX,SKCURL		; backward
			MOV		BX,SKCURH
			SUB		CX,AX
			SBB		BX,DX
			MOV		AX,CX
			MOV		DX,BX
			JNC		SKSET
			XOR		AX,AX
			XOR		DX,DX
			MOV		SKST,20
			JMP		SHORT SKSET
SKCHK:		CMP		DX,SKSIZH		; past end of file?
			JA		SKPAST
			JB		SKSET
			CMP		AX,SKSIZL
			JBE		SKSET
SKPAST:		CMP		SKACC,1
			JNE		SKEXT
			MOV		AX,SKSIZL		; read-only: stop at EOF
			MOV		DX,SKSIZH
			MOV		SKST,35
			JMP		SHORT SKSET
SKEXT:		PUSH	AX				; update: extend with zeros
			PUSH	DX
			MOV		BX,SKHAND
			MOV		DX,SKSIZL
			MOV		CX,SKSIZH
			MOV		AX,4200H
			INT		21H
			POP		DX
			POP		AX
			MOV		CX,AX
			MOV		BX,DX
			SUB		CX,SKSIZL
			SBB		BX,SKSIZH		; BX:CX zero bytes to write
SKZ1:		MOV		AX,CX
			OR		AX,BX
			JZ		SKZ3
			PUSH	CX
			PUSH	BX
			OR		BX,BX
			JNZ		SKZ2
			CMP		CX,128
			JBE		SKZ2A
SKZ2:		MOV		CX,128
SKZ2A:		PUSH	CX
			MOV		BX,SKHAND
			MOV		DX,OFFSET ZEROS
			MOV		AH,40H
			INT		21H
			POP		AX
			POP		BX
			POP		CX
			SUB		CX,AX
			SBB		BX,0
			JMP		SKZ1
SKZ3:		JMP		SHORT SKDONE
SKSET:		MOV		CX,DX
			MOV		DX,AX
			MOV		BX,SKHAND
			MOV		AX,4200H
			INT		21H
SKDONE:		MOV		AX,SKST
SKRST:		JMP		SETST

;--- LOAD (PATH$P, BIAS, SWITCH, ENTRY$P, STATUS$P)
FLOAD:		CALL	PARG
			OR		AX,AX
			JNZ		FL9J
			MOV		AX,4
			CMP		PDEV,10
			JAE		FL9J
			CMP		PHASN,0
			JNE		FL0
FL9J:		JMP		FL9
FL0:
			CALL	GETARG
			MOV		LDBIAS,AX
			CALL	GETARG
			MOV		LDSW,AX
			CALL	GETARG
			MOV		LDENTP,AX
			MOV		AX,33
			CMP		LDSW,1
			JA		FL8
			CALL	MKPATH
			MOV		DX,OFFSET PATHB
			MOV		AX,3D00H
			INT		21H
			JNC		FL1
			MOV		AX,13
			JMP		SHORT FL8
FL1:		MOV		LDHAND,AX
			CALL	LOADER
			PUSH	AX
			MOV		BX,LDHAND
			MOV		AH,3EH
			INT		21H
			POP		AX
			OR		AX,AX
			JZ		FL2
			CALL	ERRRPT			; fatal, as ISX
			JMP		CLI
FL2:		CMP		LDSW,0
			JNE		FL3
			MOV		AX,LDENT
			MOV		DI,LDENTP
			CALL	PUTW
			XOR		AX,AX
			JMP		SHORT FL8
FL3:		MOV		AX,LDENT		; switch 1: transfer control
			OR		AX,AX
			JNZ		FL4
			MOV		AX,LDLOWA
FL4:		MOV		R_SI,AX
			MOV		R_BP,STK80-2
			MOV		WORD PTR ES:[STK80-2],0
			JMP		ISRET
FL9:		CALL	GETARG			; skip BIAS, SWITCH, ENTRY$P
			CALL	GETARG
			CALL	GETARG
FL8:		JMP		SETST

;--- RENAME (OLD$P, NEW$P, STATUS$P)
FRENAM:		CALL	PARG
			OR		AX,AX
			JNZ		FN8
			MOV		AX,17
			CMP		PDEV,10
			JAE		FN8
			MOV		AX,23
			CMP		PHASN,0
			JE		FN8
			MOV		AL,PDEV
			MOV		RNDEV,AL
			CALL	MKPATH
			MOV		SI,OFFSET PATHB
			MOV		DI,OFFSET PATH2
			PUSH	ES
			PUSH	DS
			POP		ES
			MOV		CX,PLEN
			REP		MOVSB
			POP		ES
			CALL	PARG
			OR		AX,AX
			JNZ		FN9
			MOV		AX,17
			CMP		PDEV,10
			JAE		FN9
			MOV		AX,23
			CMP		PHASN,0
			JE		FN9
			MOV		AX,10
			MOV		BL,PDEV
			CMP		BL,RNDEV
			JNE		FN9
			CALL	MKPATH			; PATHB = new, PATH2 = old
			MOV		DX,OFFSET PATHB
			MOV		AX,4300H
			INT		21H
			MOV		AX,11
			JNC		FN9
			MOV		DX,OFFSET PATH2
			MOV		DI,OFFSET PATHB
			PUSH	ES
			PUSH	DS
			POP		ES
			MOV		AH,56H
			INT		21H
			POP		ES
			MOV		AX,13
			JC		FN9
			XOR		AX,AX
			JMP		SHORT FN9
FN8:		PUSH	AX
			CALL	GETARG			; skip NEW$P
			POP		AX
FN9:		JMP		SETST

;--- CONSOLE (CI$P, CO$P, STATUS$P)  -- no-op, as ISX
FCONS:		CALL	GETARG
			CALL	GETARG
			XOR		AX,AX
			JMP		SETST

;--- EXIT
FEXIT:		JMP		CLI

;--- ATTRIB (PATH$P, ATTRIB, ON$OFF, STATUS$P)  -- no-op, as ISX
FATTR:		CALL	GETARG
			CALL	GETARG
			CALL	GETARG
			XOR		AX,AX
			JMP		SETST

;--- RESCAN (AFTN, STATUS$P)
FRESC:		CALL	GETARG
			CMP		AX,1
			JE		RS1
			MOV		AX,21
			JMP		SETST
RS1:		MOV		CIIDX,0
			XOR		AX,AX
			JMP		SETST

;--- ERROR (ERRNUM, STATUS$P)
FERROR:		CALL	GETARG
			PUSH	AX
			XOR		AX,AX
			CALL	GETARG			; status first (as ISX)
			MOV		DI,AX
			XOR		AX,AX
			CALL	PUTW
			POP		AX
			XOR		AH,AH
			CALL	ERRRPT
			JMP		ISRET

;--- WHOCON (AFTN, BUFFER$P)
FWHO:		CALL	GETARG
			MOV		SI,OFFSET WHOCI
			CMP		AX,1
			JE		WH1
			MOV		SI,OFFSET WHOCO
WH1:		CALL	GETARG
			MOV		DI,AX
			MOV		CX,5
			REP		MOVSB
			JMP		ISRET
WHOCI		DB		':CI: '
WHOCO		DB		':CO: '

;--- SPATH (PATH$P, INFO$P, STATUS$P)
FSPATH:		CALL	PARG
			MOV		SPERR,AX
			CALL	GETARG
			MOV		DI,AX
			MOV		AX,SPERR
			OR		AX,AX
			JNZ		SP9
			MOV		AL,PDEV
			MOV		ES:[DI],AL
			CMP		AL,10
			JB		SP2
			MOV		CX,9			; device: zeros, type, FFH
			XOR		AL,AL
SP1:		INC		DI
			MOV		ES:[DI],AL
			LOOP	SP1
			MOV		BL,PDEV
			SUB		BL,10
			XOR		BH,BH
			MOV		AL,DEVCLS[BX]
			MOV		AH,0			; 0 input, 1 output, 2 in/out
			CMP		AL,0
			JE		SP1A
			CMP		AL,2
			JE		SP1A
			MOV		AH,1
			CMP		AL,5
			JNE		SP1A
			MOV		AH,2
SP1A:		MOV		ES:[DI+1],AH
			MOV		BYTE PTR ES:[DI+2],0FFH
			XOR		AX,AX
			JMP		SHORT SP9
SP2:		CMP		PHASN,0
			JNE		SP3
			MOV		AX,4
			JMP		SHORT SP9
SP3:		MOV		SI,OFFSET PNAME	; name/ext, zero padded
			MOV		CX,9
SP4:		INC		DI
			LODSB
			CMP		AL,' '
			JNE		SP5
			XOR		AL,AL
SP5:		MOV		ES:[DI],AL
			LOOP	SP4
			; random access device
			MOV		BYTE PTR ES:[DI+1],3
			; drive type
			MOV		BYTE PTR ES:[DI+2],1
			XOR		AX,AX
SP9:		JMP		SETST

;-----------------------------------------------------------------------
; 8080 opcode handlers, one per opcode (generated).  Each ends by
; dispatching the next opcode (NXT).  '*' marks the undocumented 8080
; aliases (NOP/JMP/RET/CALL); ED nn is reserved for ISX86's own traps.
;-----------------------------------------------------------------------

OP_00:								; NOP
			NXT

OP_01:								; LXI B,nn
			MOV		CX,WORD PTR [SI]
			ADD		SI,2
			NXT

OP_02:								; STAX B
			MOV		DI,CX
			MOV		[DI],AL
			NXT

OP_03:								; INX B
			INC		CX
			NXT

OP_04:								; INR B
			SAHF
			INC		CH
			LAHF
			NXT

OP_05:								; DCR B
			SAHF
			DEC		CH
			LAHF
			NXT

OP_06:								; MVI B,n
			MOV		CH,BYTE PTR [SI]
			INC		SI
			NXT

OP_07:								; RLC
			SAHF
			ROL		AL,1
			LAHF
			NXT

OP_08:								; *NOP
			NXT

OP_09:								; DAD B
			AND		AH,0FEH
			ADD		BX,CX
			ADC		AH,0
			NXT

OP_0A:								; LDAX B
			MOV		DI,CX
			MOV		AL,[DI]
			NXT

OP_0B:								; DCX B
			DEC		CX
			NXT

OP_0C:								; INR C
			SAHF
			INC		CL
			LAHF
			NXT

OP_0D:								; DCR C
			SAHF
			DEC		CL
			LAHF
			NXT

OP_0E:								; MVI C,n
			MOV		CL,BYTE PTR [SI]
			INC		SI
			NXT

OP_0F:								; RRC
			SAHF
			ROR		AL,1
			LAHF
			NXT

OP_10:								; *NOP
			NXT

OP_11:								; LXI D,nn
			MOV		DX,WORD PTR [SI]
			ADD		SI,2
			NXT

OP_12:								; STAX D
			MOV		DI,DX
			MOV		[DI],AL
			NXT

OP_13:								; INX D
			INC		DX
			NXT

OP_14:								; INR D
			SAHF
			INC		DH
			LAHF
			NXT

OP_15:								; DCR D
			SAHF
			DEC		DH
			LAHF
			NXT

OP_16:								; MVI D,n
			MOV		DH,BYTE PTR [SI]
			INC		SI
			NXT

OP_17:								; RAL
			SAHF
			RCL		AL,1
			LAHF
			NXT

OP_18:								; *NOP
			NXT

OP_19:								; DAD D
			AND		AH,0FEH
			ADD		BX,DX
			ADC		AH,0
			NXT

OP_1A:								; LDAX D
			MOV		DI,DX
			MOV		AL,[DI]
			NXT

OP_1B:								; DCX D
			DEC		DX
			NXT

OP_1C:								; INR E
			SAHF
			INC		DL
			LAHF
			NXT

OP_1D:								; DCR E
			SAHF
			DEC		DL
			LAHF
			NXT

OP_1E:								; MVI E,n
			MOV		DL,BYTE PTR [SI]
			INC		SI
			NXT

OP_1F:								; RAR
			SAHF
			RCR		AL,1
			LAHF
			NXT

OP_20:								; *NOP
			NXT

OP_21:								; LXI H,nn
			MOV		BX,WORD PTR [SI]
			ADD		SI,2
			NXT

OP_22:								; SHLD nn
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			MOV		[DI],BX
			NXT

OP_23:								; INX H
			INC		BX
			NXT

OP_24:								; INR H
			SAHF
			INC		BH
			LAHF
			NXT

OP_25:								; DCR H
			SAHF
			DEC		BH
			LAHF
			NXT

OP_26:								; MVI H,n
			MOV		BH,BYTE PTR [SI]
			INC		SI
			NXT

OP_27:								; DAA
			SAHF
			DAA
			LAHF
			NXT

OP_28:								; *NOP
			NXT

OP_29:								; DAD H
			AND		AH,0FEH
			ADD		BX,BX
			ADC		AH,0
			NXT

OP_2A:								; LHLD nn
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			MOV		BX,[DI]
			NXT

OP_2B:								; DCX H
			DEC		BX
			NXT

OP_2C:								; INR L
			SAHF
			INC		BL
			LAHF
			NXT

OP_2D:								; DCR L
			SAHF
			DEC		BL
			LAHF
			NXT

OP_2E:								; MVI L,n
			MOV		BL,BYTE PTR [SI]
			INC		SI
			NXT

OP_2F:								; CMA
			NOT		AL
			NXT

OP_30:								; *NOP
			NXT

OP_31:								; LXI SP,nn
			MOV		BP,WORD PTR [SI]
			ADD		SI,2
			NXT

OP_32:								; STA nn
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			MOV		[DI],AL
			NXT

OP_33:								; INX SP
			INC		BP
			NXT

OP_34:								; INR M
			SAHF
			INC		BYTE PTR [BX]
			LAHF
			NXT

OP_35:								; DCR M
			SAHF
			DEC		BYTE PTR [BX]
			LAHF
			NXT

OP_36:								; MVI M,n
			MOV		DI,WORD PTR [SI]
			INC		SI
			XCHG	AX,DI
			MOV		[BX],AL
			XCHG	AX,DI
			NXT

OP_37:								; STC
			OR		AH,1
			NXT

OP_38:								; *NOP
			NXT

OP_39:								; DAD SP
			AND		AH,0FEH
			ADD		BX,BP
			ADC		AH,0
			NXT

OP_3A:								; LDA nn
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			MOV		AL,[DI]
			NXT

OP_3B:								; DCX SP
			DEC		BP
			NXT

OP_3C:								; INR A
			SAHF
			INC		AL
			LAHF
			NXT

OP_3D:								; DCR A
			SAHF
			DEC		AL
			LAHF
			NXT

OP_3E:								; MVI A,n
			MOV		AL,BYTE PTR [SI]
			INC		SI
			NXT

OP_3F:								; CMC
			XOR		AH,1
			NXT

OP_40:								; MOV B,B
			NXT

OP_41:								; MOV B,C
			MOV		CH,CL
			NXT

OP_42:								; MOV B,D
			MOV		CH,DH
			NXT

OP_43:								; MOV B,E
			MOV		CH,DL
			NXT

OP_44:								; MOV B,H
			MOV		CH,BH
			NXT

OP_45:								; MOV B,L
			MOV		CH,BL
			NXT

OP_46:								; MOV B,M
			MOV		CH,BYTE PTR [BX]
			NXT

OP_47:								; MOV B,A
			MOV		CH,AL
			NXT

OP_48:								; MOV C,B
			MOV		CL,CH
			NXT

OP_49:								; MOV C,C
			NXT

OP_4A:								; MOV C,D
			MOV		CL,DH
			NXT

OP_4B:								; MOV C,E
			MOV		CL,DL
			NXT

OP_4C:								; MOV C,H
			MOV		CL,BH
			NXT

OP_4D:								; MOV C,L
			MOV		CL,BL
			NXT

OP_4E:								; MOV C,M
			MOV		CL,BYTE PTR [BX]
			NXT

OP_4F:								; MOV C,A
			MOV		CL,AL
			NXT

OP_50:								; MOV D,B
			MOV		DH,CH
			NXT

OP_51:								; MOV D,C
			MOV		DH,CL
			NXT

OP_52:								; MOV D,D
			NXT

OP_53:								; MOV D,E
			MOV		DH,DL
			NXT

OP_54:								; MOV D,H
			MOV		DH,BH
			NXT

OP_55:								; MOV D,L
			MOV		DH,BL
			NXT

OP_56:								; MOV D,M
			MOV		DH,BYTE PTR [BX]
			NXT

OP_57:								; MOV D,A
			MOV		DH,AL
			NXT

OP_58:								; MOV E,B
			MOV		DL,CH
			NXT

OP_59:								; MOV E,C
			MOV		DL,CL
			NXT

OP_5A:								; MOV E,D
			MOV		DL,DH
			NXT

OP_5B:								; MOV E,E
			NXT

OP_5C:								; MOV E,H
			MOV		DL,BH
			NXT

OP_5D:								; MOV E,L
			MOV		DL,BL
			NXT

OP_5E:								; MOV E,M
			MOV		DL,BYTE PTR [BX]
			NXT

OP_5F:								; MOV E,A
			MOV		DL,AL
			NXT

OP_60:								; MOV H,B
			MOV		BH,CH
			NXT

OP_61:								; MOV H,C
			MOV		BH,CL
			NXT

OP_62:								; MOV H,D
			MOV		BH,DH
			NXT

OP_63:								; MOV H,E
			MOV		BH,DL
			NXT

OP_64:								; MOV H,H
			NXT

OP_65:								; MOV H,L
			MOV		BH,BL
			NXT

OP_66:								; MOV H,M
			MOV		BH,BYTE PTR [BX]
			NXT

OP_67:								; MOV H,A
			MOV		BH,AL
			NXT

OP_68:								; MOV L,B
			MOV		BL,CH
			NXT

OP_69:								; MOV L,C
			MOV		BL,CL
			NXT

OP_6A:								; MOV L,D
			MOV		BL,DH
			NXT

OP_6B:								; MOV L,E
			MOV		BL,DL
			NXT

OP_6C:								; MOV L,H
			MOV		BL,BH
			NXT

OP_6D:								; MOV L,L
			NXT

OP_6E:								; MOV L,M
			MOV		BL,BYTE PTR [BX]
			NXT

OP_6F:								; MOV L,A
			MOV		BL,AL
			NXT

OP_70:								; MOV M,B
			MOV		BYTE PTR [BX],CH
			NXT

OP_71:								; MOV M,C
			MOV		BYTE PTR [BX],CL
			NXT

OP_72:								; MOV M,D
			MOV		BYTE PTR [BX],DH
			NXT

OP_73:								; MOV M,E
			MOV		BYTE PTR [BX],DL
			NXT

OP_74:								; MOV M,H
			MOV		BYTE PTR [BX],BH
			NXT

OP_75:								; MOV M,L
			MOV		BYTE PTR [BX],BL
			NXT

OP_76:								; HLT
			JMP		OP_HLT

OP_77:								; MOV M,A
			MOV		BYTE PTR [BX],AL
			NXT

OP_78:								; MOV A,B
			MOV		AL,CH
			NXT

OP_79:								; MOV A,C
			MOV		AL,CL
			NXT

OP_7A:								; MOV A,D
			MOV		AL,DH
			NXT

OP_7B:								; MOV A,E
			MOV		AL,DL
			NXT

OP_7C:								; MOV A,H
			MOV		AL,BH
			NXT

OP_7D:								; MOV A,L
			MOV		AL,BL
			NXT

OP_7E:								; MOV A,M
			MOV		AL,BYTE PTR [BX]
			NXT

OP_7F:								; MOV A,A
			NXT

OP_80:								; ADD B
			ADD		AL,CH
			LAHF
			NXT

OP_81:								; ADD C
			ADD		AL,CL
			LAHF
			NXT

OP_82:								; ADD D
			ADD		AL,DH
			LAHF
			NXT

OP_83:								; ADD E
			ADD		AL,DL
			LAHF
			NXT

OP_84:								; ADD H
			ADD		AL,BH
			LAHF
			NXT

OP_85:								; ADD L
			ADD		AL,BL
			LAHF
			NXT

OP_86:								; ADD M
			ADD		AL,BYTE PTR [BX]
			LAHF
			NXT

OP_87:								; ADD A
			ADD		AL,AL
			LAHF
			NXT

OP_88:								; ADC B
			SAHF
			ADC		AL,CH
			LAHF
			NXT

OP_89:								; ADC C
			SAHF
			ADC		AL,CL
			LAHF
			NXT

OP_8A:								; ADC D
			SAHF
			ADC		AL,DH
			LAHF
			NXT

OP_8B:								; ADC E
			SAHF
			ADC		AL,DL
			LAHF
			NXT

OP_8C:								; ADC H
			SAHF
			ADC		AL,BH
			LAHF
			NXT

OP_8D:								; ADC L
			SAHF
			ADC		AL,BL
			LAHF
			NXT

OP_8E:								; ADC M
			SAHF
			ADC		AL,BYTE PTR [BX]
			LAHF
			NXT

OP_8F:								; ADC A
			SAHF
			ADC		AL,AL
			LAHF
			NXT

OP_90:								; SUB B
			SUB		AL,CH
			LAHF
			NXT

OP_91:								; SUB C
			SUB		AL,CL
			LAHF
			NXT

OP_92:								; SUB D
			SUB		AL,DH
			LAHF
			NXT

OP_93:								; SUB E
			SUB		AL,DL
			LAHF
			NXT

OP_94:								; SUB H
			SUB		AL,BH
			LAHF
			NXT

OP_95:								; SUB L
			SUB		AL,BL
			LAHF
			NXT

OP_96:								; SUB M
			SUB		AL,BYTE PTR [BX]
			LAHF
			NXT

OP_97:								; SUB A
			SUB		AL,AL
			LAHF
			NXT

OP_98:								; SBB B
			SAHF
			SBB		AL,CH
			LAHF
			NXT

OP_99:								; SBB C
			SAHF
			SBB		AL,CL
			LAHF
			NXT

OP_9A:								; SBB D
			SAHF
			SBB		AL,DH
			LAHF
			NXT

OP_9B:								; SBB E
			SAHF
			SBB		AL,DL
			LAHF
			NXT

OP_9C:								; SBB H
			SAHF
			SBB		AL,BH
			LAHF
			NXT

OP_9D:								; SBB L
			SAHF
			SBB		AL,BL
			LAHF
			NXT

OP_9E:								; SBB M
			SAHF
			SBB		AL,BYTE PTR [BX]
			LAHF
			NXT

OP_9F:								; SBB A
			SAHF
			SBB		AL,AL
			LAHF
			NXT

OP_A0:								; ANA B
			AND		AL,CH
			LAHF
			NXT

OP_A1:								; ANA C
			AND		AL,CL
			LAHF
			NXT

OP_A2:								; ANA D
			AND		AL,DH
			LAHF
			NXT

OP_A3:								; ANA E
			AND		AL,DL
			LAHF
			NXT

OP_A4:								; ANA H
			AND		AL,BH
			LAHF
			NXT

OP_A5:								; ANA L
			AND		AL,BL
			LAHF
			NXT

OP_A6:								; ANA M
			AND		AL,BYTE PTR [BX]
			LAHF
			NXT

OP_A7:								; ANA A
			AND		AL,AL
			LAHF
			NXT

OP_A8:								; XRA B
			XOR		AL,CH
			LAHF
			NXT

OP_A9:								; XRA C
			XOR		AL,CL
			LAHF
			NXT

OP_AA:								; XRA D
			XOR		AL,DH
			LAHF
			NXT

OP_AB:								; XRA E
			XOR		AL,DL
			LAHF
			NXT

OP_AC:								; XRA H
			XOR		AL,BH
			LAHF
			NXT

OP_AD:								; XRA L
			XOR		AL,BL
			LAHF
			NXT

OP_AE:								; XRA M
			XOR		AL,BYTE PTR [BX]
			LAHF
			NXT

OP_AF:								; XRA A
			XOR		AL,AL
			LAHF
			NXT

OP_B0:								; ORA B
			OR		AL,CH
			LAHF
			NXT

OP_B1:								; ORA C
			OR		AL,CL
			LAHF
			NXT

OP_B2:								; ORA D
			OR		AL,DH
			LAHF
			NXT

OP_B3:								; ORA E
			OR		AL,DL
			LAHF
			NXT

OP_B4:								; ORA H
			OR		AL,BH
			LAHF
			NXT

OP_B5:								; ORA L
			OR		AL,BL
			LAHF
			NXT

OP_B6:								; ORA M
			OR		AL,BYTE PTR [BX]
			LAHF
			NXT

OP_B7:								; ORA A
			OR		AL,AL
			LAHF
			NXT

OP_B8:								; CMP B
			CMP		AL,CH
			LAHF
			NXT

OP_B9:								; CMP C
			CMP		AL,CL
			LAHF
			NXT

OP_BA:								; CMP D
			CMP		AL,DH
			LAHF
			NXT

OP_BB:								; CMP E
			CMP		AL,DL
			LAHF
			NXT

OP_BC:								; CMP H
			CMP		AL,BH
			LAHF
			NXT

OP_BD:								; CMP L
			CMP		AL,BL
			LAHF
			NXT

OP_BE:								; CMP M
			CMP		AL,BYTE PTR [BX]
			LAHF
			NXT

OP_BF:								; CMP A
			CMP		AL,AL
			LAHF
			NXT

OP_C0:								; RNZ
			TEST	AH,040H
			JNZ		OP_C0S
			MOV		SI,WORD PTR DS:[BP]
			ADD		BP,2
			NXT
OP_C0S:
			NXT

OP_C1:								; POP B
			MOV		CX,WORD PTR DS:[BP]
			ADD		BP,2
			NXT

OP_C2:								; JNZ nn
			TEST	AH,040H
			JNZ		OP_C2S
			MOV		SI,WORD PTR [SI]
			NXT
OP_C2S:
			ADD		SI,2
			NXT

OP_C3:								; JMP nn
			MOV		SI,WORD PTR [SI]
			NXT

OP_C4:								; CNZ nn
			TEST	AH,040H
			JNZ		OP_C4S
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,DI
			NXT
OP_C4S:
			ADD		SI,2
			NXT

OP_C5:								; PUSH B
			SUB		BP,2
			MOV		WORD PTR DS:[BP],CX
			NXT

OP_C6:								; ADI n
			ADD		AL,BYTE PTR [SI]
			LAHF
			INC		SI
			NXT

OP_C7:								; RST 0
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,000H
			NXT

OP_C8:								; RZ
			TEST	AH,040H
			JZ		OP_C8S
			MOV		SI,WORD PTR DS:[BP]
			ADD		BP,2
			NXT
OP_C8S:
			NXT

OP_C9:								; RET
			MOV		SI,WORD PTR DS:[BP]
			ADD		BP,2
			NXT

OP_CA:								; JZ nn
			TEST	AH,040H
			JZ		OP_CAS
			MOV		SI,WORD PTR [SI]
			NXT
OP_CAS:
			ADD		SI,2
			NXT

OP_CB:								; *JMP nn
			MOV		SI,WORD PTR [SI]
			NXT

OP_CC:								; CZ nn
			TEST	AH,040H
			JZ		OP_CCS
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,DI
			NXT
OP_CCS:
			ADD		SI,2
			NXT

OP_CD:								; CALL nn
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,DI
			NXT

OP_CE:								; ACI n
			SAHF
			ADC		AL,BYTE PTR [SI]
			LAHF
			INC		SI
			NXT

OP_CF:								; RST 1
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,008H
			NXT

OP_D0:								; RNC
			TEST	AH,001H
			JNZ		OP_D0S
			MOV		SI,WORD PTR DS:[BP]
			ADD		BP,2
			NXT
OP_D0S:
			NXT

OP_D1:								; POP D
			MOV		DX,WORD PTR DS:[BP]
			ADD		BP,2
			NXT

OP_D2:								; JNC nn
			TEST	AH,001H
			JNZ		OP_D2S
			MOV		SI,WORD PTR [SI]
			NXT
OP_D2S:
			ADD		SI,2
			NXT

OP_D3:								; OUT n
			INC		SI
			NXT

OP_D4:								; CNC nn
			TEST	AH,001H
			JNZ		OP_D4S
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,DI
			NXT
OP_D4S:
			ADD		SI,2
			NXT

OP_D5:								; PUSH D
			SUB		BP,2
			MOV		WORD PTR DS:[BP],DX
			NXT

OP_D6:								; SUI n
			SUB		AL,BYTE PTR [SI]
			LAHF
			INC		SI
			NXT

OP_D7:								; RST 2
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,010H
			NXT

OP_D8:								; RC
			TEST	AH,001H
			JZ		OP_D8S
			MOV		SI,WORD PTR DS:[BP]
			ADD		BP,2
			NXT
OP_D8S:
			NXT

OP_D9:								; *RET
			MOV		SI,WORD PTR DS:[BP]
			ADD		BP,2
			NXT

OP_DA:								; JC nn
			TEST	AH,001H
			JZ		OP_DAS
			MOV		SI,WORD PTR [SI]
			NXT
OP_DAS:
			ADD		SI,2
			NXT

OP_DB:								; IN n
			INC		SI
			MOV		AL,0FFH
			NXT

OP_DC:								; CC nn
			TEST	AH,001H
			JZ		OP_DCS
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,DI
			NXT
OP_DCS:
			ADD		SI,2
			NXT

OP_DD:								; *CALL nn
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,DI
			NXT

OP_DE:								; SBI n
			SAHF
			SBB		AL,BYTE PTR [SI]
			LAHF
			INC		SI
			NXT

OP_DF:								; RST 3
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,018H
			NXT

OP_E0:								; RPO
			TEST	AH,004H
			JNZ		OP_E0S
			MOV		SI,WORD PTR DS:[BP]
			ADD		BP,2
			NXT
OP_E0S:
			NXT

OP_E1:								; POP H
			MOV		BX,WORD PTR DS:[BP]
			ADD		BP,2
			NXT

OP_E2:								; JPO nn
			TEST	AH,004H
			JNZ		OP_E2S
			MOV		SI,WORD PTR [SI]
			NXT
OP_E2S:
			ADD		SI,2
			NXT

OP_E3:								; XTHL
			XCHG	BX,WORD PTR DS:[BP]
			NXT

OP_E4:								; CPO nn
			TEST	AH,004H
			JNZ		OP_E4S
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,DI
			NXT
OP_E4S:
			ADD		SI,2
			NXT

OP_E5:								; PUSH H
			SUB		BP,2
			MOV		WORD PTR DS:[BP],BX
			NXT

OP_E6:								; ANI n
			AND		AL,BYTE PTR [SI]
			LAHF
			INC		SI
			NXT

OP_E7:								; RST 4
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,020H
			NXT

OP_E8:								; RPE
			TEST	AH,004H
			JZ		OP_E8S
			MOV		SI,WORD PTR DS:[BP]
			ADD		BP,2
			NXT
OP_E8S:
			NXT

OP_E9:								; PCHL
			MOV		SI,BX
			NXT

OP_EA:								; JPE nn
			TEST	AH,004H
			JZ		OP_EAS
			MOV		SI,WORD PTR [SI]
			NXT
OP_EAS:
			ADD		SI,2
			NXT

OP_EB:								; XCHG
			XCHG	BX,DX
			NXT

OP_EC:								; CPE nn
			TEST	AH,004H
			JZ		OP_ECS
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,DI
			NXT
OP_ECS:
			ADD		SI,2
			NXT

OP_ED:								; ISX86 trap (ED nn)
			JMP		OP_TRAP

OP_EE:								; XRI n
			XOR		AL,BYTE PTR [SI]
			LAHF
			INC		SI
			NXT

OP_EF:								; RST 5
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,028H
			NXT

OP_F0:								; RP
			TEST	AH,080H
			JNZ		OP_F0S
			MOV		SI,WORD PTR DS:[BP]
			ADD		BP,2
			NXT
OP_F0S:
			NXT

OP_F1:								; POP PSW
			MOV		AX,WORD PTR DS:[BP]
			ADD		BP,2
			XCHG	AL,AH
			AND		AH,0D5H
			OR		AH,2
			NXT

OP_F2:								; JP nn
			TEST	AH,080H
			JNZ		OP_F2S
			MOV		SI,WORD PTR [SI]
			NXT
OP_F2S:
			ADD		SI,2
			NXT

OP_F3:								; DI
			NXT

OP_F4:								; CP nn
			TEST	AH,080H
			JNZ		OP_F4S
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,DI
			NXT
OP_F4S:
			ADD		SI,2
			NXT

OP_F5:								; PUSH PSW
			XCHG	AL,AH
			SUB		BP,2
			MOV		WORD PTR DS:[BP],AX
			XCHG	AL,AH
			NXT

OP_F6:								; ORI n
			OR		AL,BYTE PTR [SI]
			LAHF
			INC		SI
			NXT

OP_F7:								; RST 6
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,030H
			NXT

OP_F8:								; RM
			TEST	AH,080H
			JZ		OP_F8S
			MOV		SI,WORD PTR DS:[BP]
			ADD		BP,2
			NXT
OP_F8S:
			NXT

OP_F9:								; SPHL
			MOV		BP,BX
			NXT

OP_FA:								; JM nn
			TEST	AH,080H
			JZ		OP_FAS
			MOV		SI,WORD PTR [SI]
			NXT
OP_FAS:
			ADD		SI,2
			NXT

OP_FB:								; EI
			NXT

OP_FC:								; CM nn
			TEST	AH,080H
			JZ		OP_FCS
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,DI
			NXT
OP_FCS:
			ADD		SI,2
			NXT

OP_FD:								; *CALL nn
			MOV		DI,WORD PTR [SI]
			ADD		SI,2
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,DI
			NXT

OP_FE:								; CPI n
			CMP		AL,BYTE PTR [SI]
			LAHF
			INC		SI
			NXT

OP_FF:								; RST 7
			SUB		BP,2
			MOV		WORD PTR DS:[BP],SI
			MOV		SI,038H
			NXT

;-----------------------------------------------------------------------
; Data
;-----------------------------------------------------------------------
OPTAB		LABEL	WORD
			DW		OP_00,OP_01,OP_02,OP_03,OP_04,OP_05,OP_06,OP_07
			DW		OP_08,OP_09,OP_0A,OP_0B,OP_0C,OP_0D,OP_0E,OP_0F
			DW		OP_10,OP_11,OP_12,OP_13,OP_14,OP_15,OP_16,OP_17
			DW		OP_18,OP_19,OP_1A,OP_1B,OP_1C,OP_1D,OP_1E,OP_1F
			DW		OP_20,OP_21,OP_22,OP_23,OP_24,OP_25,OP_26,OP_27
			DW		OP_28,OP_29,OP_2A,OP_2B,OP_2C,OP_2D,OP_2E,OP_2F
			DW		OP_30,OP_31,OP_32,OP_33,OP_34,OP_35,OP_36,OP_37
			DW		OP_38,OP_39,OP_3A,OP_3B,OP_3C,OP_3D,OP_3E,OP_3F
			DW		OP_40,OP_41,OP_42,OP_43,OP_44,OP_45,OP_46,OP_47
			DW		OP_48,OP_49,OP_4A,OP_4B,OP_4C,OP_4D,OP_4E,OP_4F
			DW		OP_50,OP_51,OP_52,OP_53,OP_54,OP_55,OP_56,OP_57
			DW		OP_58,OP_59,OP_5A,OP_5B,OP_5C,OP_5D,OP_5E,OP_5F
			DW		OP_60,OP_61,OP_62,OP_63,OP_64,OP_65,OP_66,OP_67
			DW		OP_68,OP_69,OP_6A,OP_6B,OP_6C,OP_6D,OP_6E,OP_6F
			DW		OP_70,OP_71,OP_72,OP_73,OP_74,OP_75,OP_76,OP_77
			DW		OP_78,OP_79,OP_7A,OP_7B,OP_7C,OP_7D,OP_7E,OP_7F
			DW		OP_80,OP_81,OP_82,OP_83,OP_84,OP_85,OP_86,OP_87
			DW		OP_88,OP_89,OP_8A,OP_8B,OP_8C,OP_8D,OP_8E,OP_8F
			DW		OP_90,OP_91,OP_92,OP_93,OP_94,OP_95,OP_96,OP_97
			DW		OP_98,OP_99,OP_9A,OP_9B,OP_9C,OP_9D,OP_9E,OP_9F
			DW		OP_A0,OP_A1,OP_A2,OP_A3,OP_A4,OP_A5,OP_A6,OP_A7
			DW		OP_A8,OP_A9,OP_AA,OP_AB,OP_AC,OP_AD,OP_AE,OP_AF
			DW		OP_B0,OP_B1,OP_B2,OP_B3,OP_B4,OP_B5,OP_B6,OP_B7
			DW		OP_B8,OP_B9,OP_BA,OP_BB,OP_BC,OP_BD,OP_BE,OP_BF
			DW		OP_C0,OP_C1,OP_C2,OP_C3,OP_C4,OP_C5,OP_C6,OP_C7
			DW		OP_C8,OP_C9,OP_CA,OP_CB,OP_CC,OP_CD,OP_CE,OP_CF
			DW		OP_D0,OP_D1,OP_D2,OP_D3,OP_D4,OP_D5,OP_D6,OP_D7
			DW		OP_D8,OP_D9,OP_DA,OP_DB,OP_DC,OP_DD,OP_DE,OP_DF
			DW		OP_E0,OP_E1,OP_E2,OP_E3,OP_E4,OP_E5,OP_E6,OP_E7
			DW		OP_E8,OP_E9,OP_EA,OP_EB,OP_EC,OP_ED,OP_EE,OP_EF
			DW		OP_F0,OP_F1,OP_F2,OP_F3,OP_F4,OP_F5,OP_F6,OP_F7
			DW		OP_F8,OP_F9,OP_FA,OP_FB,OP_FC,OP_FD,OP_FE,OP_FF

PSPSEG		DW		0
MEMSEG		DW		0
INDEV		DB		0
ONESHOT		DB		0
BRKFLG		DB		0
TRLVL		DB		0
CURDRV		DB		0
IOBYTE		DB		0
RDUP		DB		0
RDCH		DB		0
CMDPTR		DW		0
R_AX		DW		0
R_BX		DW		0
R_CX		DW		0
R_DX		DW		0
R_SI		DW		0
R_BP		DW		0
PBLK		DW		0
; parser
PDEV		DB		0
PHASN		DB		0
PNAME		DB		6 DUP(' ')
PEXT		DB		3 DUP(' ')
; loader
LDHAND		DW		0
LDBIAS		DW		0
LDENT		DW		0
LDLOWA		DW		0
LDCNT		DW		0
LDPTR		DW		0
LDREM		DW		0
LDSW		DW		0
LDENTP		DW		0
LDTYP		DB		0
LDSUM		DB		0
LDANY		DB		0
; ISIS call scratch
OPAFTP		DW		0
OPERR		DW		0
OPACC		DW		0
OPECHO		DW		0
OPSLOT		DW		0
RWBUF		DW		0
RWCNT		DW		0
RWACTP		DW		0
RWACT		DW		0
SKMODE		DW		0
SKBLKP		DW		0
SKBYTP		DW		0
SKHAND		DW		0
SKCURL		DW		0
SKCURH		DW		0
SKSIZL		DW		0
SKSIZH		DW		0
SKST		DW		0
SKACC		DB		0
RNDEV		DB		0
SPERR		DW		0
; :CI: line buffer
CILEN		DW		0
CIIDX		DW		0
CIBUF		DB		132 DUP(0)
LINE		DB		132 DUP(0)
KBUF		DB		130 DUP(0)
; AFTN slots
STYPE		DB		NSLOT DUP(0)
SACC		DB		NSLOT DUP(0)
SHAND		DW		NSLOT DUP(0)
SPATHS		DB		NSLOT*PLEN DUP(0)
; drive map :F0:..:F9: (PLEN-14 bytes each, empty = current dir)
DMAP		DB		10*(PLEN-14) DUP(0)
PATHB		DB		PLEN DUP(0)
PATH2		DB		PLEN DUP(0)
DTA			DB		64 DUP(0)
ZEROS		DB		128 DUP(0)
LDBUF		DB		512 DUP(0)
			CODE	ENDS

			STK		SEGMENT STACK
			DW		256 DUP(0)
STKTOP		LABEL	WORD
			STK		ENDS

			ZZZ		SEGMENT
			ZZZ		ENDS
			END		START
