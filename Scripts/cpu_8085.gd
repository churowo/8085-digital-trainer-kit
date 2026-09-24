class_name CPU8085
extends RefCounted

var A: int = 0
var B: int = 0; var C: int = 0
var D: int = 0; var E: int = 0
var H: int = 0; var L: int = 0
var SP: int = 0xFFFF
var PC: int = 0x2000 # Typical RAM start for user programs

var flag_S: bool = false
var flag_Z: bool = false
var flag_AC: bool = false
var flag_P: bool = false
var flag_CY: bool = false
var halted: bool = false
var interrupts_enabled: bool = false

var memory: PackedByteArray = PackedByteArray()


var input_ports: PackedByteArray = PackedByteArray()
var output_ports: PackedByteArray = PackedByteArray()
var written: PackedByteArray = PackedByteArray()

var INSTR_LENGTH: PackedByteArray = _build_length_table()

static func _build_length_table() -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(256)
	t.fill(1)
	for op in [0x01, 0x11, 0x21, 0x31, 0xC3, 0xC2, 0xCA, 0xD2, 0xDA, 0xE2,
			0xEA, 0xF2, 0xFA, 0xCD, 0xC4, 0xCC, 0xD4, 0xDC, 0xE4, 0xEC,
			0xF4, 0xFC, 0x22, 0x2A, 0x32, 0x3A]:
		t[op] = 3
	for op in [0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E, 0xC6, 0xCE,
			0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE, 0xD3, 0xDB]:
		t[op] = 2
	return t

func _init() -> void:
	memory.resize(65536)
	memory.fill(0)
	input_ports.resize(256)
	output_ports.resize(256)
	written.resize(65536)
	written.fill(0)

func reset() -> void:
	A = 0; B = 0; C = 0; D = 0; E = 0; H = 0; L = 0
	SP = 0xFFFF
	PC = 0x2000
	flag_S = false; flag_Z = false; flag_AC = false
	flag_P = false; flag_CY = false
	halted = false
	interrupts_enabled = false

func read_byte(addr: int) -> int:
	return memory[addr & 0xFFFF]

func write_byte(addr: int, val: int) -> void:
	memory[addr & 0xFFFF] = val & 0xFF
	written[addr & 0xFFFF] = 1


func is_written(addr: int) -> bool:
	return written[addr & 0xFFFF] == 1


func _update_szp(val: int) -> void:
	val &= 0xFF
	flag_Z = (val == 0)
	flag_S = (val & 0x80) != 0
	var count: int = 0
	for i in range(8):
		if (val >> i) & 1:
			count += 1
	flag_P = (count % 2 == 0)


func get_register(name: String) -> int:
	match name:
		"A": return A
		"B": return B
		"C": return C
		"D": return D
		"E": return E
		"H": return H
		"L": return L
		"SP": return SP
		"PC": return PC
		"F": return _get_flags_byte()
		"BC": return (B << 8) | C
		"DE": return (D << 8) | E
		"HL": return (H << 8) | L
	push_warning("get_register: unknown register '%s'" % name)
	return 0

func set_register(name: String, val: int) -> void:
	match name:
		"A": A = val & 0xFF
		"B": B = val & 0xFF
		"C": C = val & 0xFF
		"D": D = val & 0xFF
		"E": E = val & 0xFF
		"H": H = val & 0xFF
		"L": L = val & 0xFF
		"SP": SP = val & 0xFFFF
		"PC": PC = val & 0xFFFF
		"F": _set_flags_byte(val & 0xFF)
		"BC": B = (val >> 8) & 0xFF; C = val & 0xFF
		"DE": D = (val >> 8) & 0xFF; E = val & 0xFF
		"HL": H = (val >> 8) & 0xFF; L = val & 0xFF
		_: push_warning("set_register: unknown register '%s'" % name)

# Standard 8085 flag byte layout: S Z 0 AC 0 P 1 CY
func _get_flags_byte() -> int:
	return (int(flag_S) << 7) | (int(flag_Z) << 6) | (int(flag_AC) << 4) \
		| (int(flag_P) << 2) | (1 << 1) | int(flag_CY)

func _set_flags_byte(v: int) -> void:
	flag_S = (v & 0x80) != 0
	flag_Z = (v & 0x40) != 0
	flag_AC = (v & 0x10) != 0
	flag_P = (v & 0x04) != 0
	flag_CY = (v & 0x01) != 0

# 3-bit register field used throughout the opcode map: 0=B 1=C 2=D 3=E 4=H
# 5=L 6=M(memory at HL) 7=A
func _get_r(code: int) -> int:
	match code:
		0: return B
		1: return C
		2: return D
		3: return E
		4: return H
		5: return L
		6: return read_byte((H << 8) | L)
		7: return A
	return 0

func _set_r(code: int, val: int) -> void:
	val &= 0xFF
	match code:
		0: B = val
		1: C = val
		2: D = val
		3: E = val
		4: H = val
		5: L = val
		6: write_byte((H << 8) | L, val)
		7: A = val

# 2-bit register-pair field: 0=BC 1=DE 2=HL 3=SP
func _get_rp(code: int) -> int:
	match code:
		0: return (B << 8) | C
		1: return (D << 8) | E
		2: return (H << 8) | L
		3: return SP
	return 0

func _set_rp(code: int, val: int) -> void:
	val &= 0xFFFF
	match code:
		0: B = (val >> 8) & 0xFF; C = val & 0xFF
		1: D = (val >> 8) & 0xFF; E = val & 0xFF
		2: H = (val >> 8) & 0xFF; L = val & 0xFF
		3: SP = val

# Same but for PUSH/POP, where code 3 means PSW (A + flags) instead of SP
func _get_rp_push(code: int) -> int:
	if code == 3:
		return (A << 8) | _get_flags_byte()
	return _get_rp(code)

func _set_rp_push(code: int, val: int) -> void:
	if code == 3:
		A = (val >> 8) & 0xFF
		_set_flags_byte(val & 0xFF)
	else:
		_set_rp(code, val)

func _imm16() -> int:
	var low: int = read_byte(PC)
	var high: int = read_byte((PC + 1) & 0xFFFF)
	PC = (PC + 2) & 0xFFFF
	return (high << 8) | low

func _push16(val: int) -> void:
	SP = (SP - 1) & 0xFFFF
	write_byte(SP, (val >> 8) & 0xFF)
	SP = (SP - 1) & 0xFFFF
	write_byte(SP, val & 0xFF)

func _pop16() -> int:
	var low: int = read_byte(SP)
	SP = (SP + 1) & 0xFFFF
	var high: int = read_byte(SP)
	SP = (SP + 1) & 0xFFFF
	return (high << 8) | low

func _call(addr: int) -> void:
	_push16(PC)
	PC = addr & 0xFFFF

# Condition codes used by conditional jump/call/return: 0=NZ 1=Z 2=NC 3=C
# 4=PO 5=PE 6=P(positive) 7=M(minus)
func _check_condition(code: int) -> bool:
	match code:
		0: return not flag_Z
		1: return flag_Z
		2: return not flag_CY
		3: return flag_CY
		4: return not flag_P
		5: return flag_P
		6: return not flag_S
		7: return flag_S
	return false

# ALU helpers

func _alu_add(val: int, with_carry: bool) -> void:
	var carry_in: int = 1 if (with_carry and flag_CY) else 0
	var res: int = A + val + carry_in
	flag_AC = ((A & 0x0F) + (val & 0x0F) + carry_in) > 0x0F
	flag_CY = res > 0xFF
	A = res & 0xFF
	_update_szp(A)


func _alu_sub(val: int, with_borrow: bool) -> void:
	var borrow_in: int = 1 if (with_borrow and flag_CY) else 0
	var res: int = A - val - borrow_in
	flag_AC = ((A & 0x0F) - (val & 0x0F) - borrow_in) >= 0
	flag_CY = res < 0
	A = res & 0xFF
	_update_szp(A)


func _alu_and(val: int) -> void:
	A = A & val
	flag_CY = false
	flag_AC = true
	_update_szp(A)

func _alu_xor(val: int) -> void:
	A = A ^ val
	flag_CY = false
	flag_AC = false
	_update_szp(A)

func _alu_or(val: int) -> void:
	A = A | val
	flag_CY = false
	flag_AC = false
	_update_szp(A)


func _alu_cmp(val: int) -> void:
	var res: int = A - val
	flag_CY = res < 0
	flag_AC = ((A & 0x0F) - (val & 0x0F)) >= 0
	_update_szp(res & 0xFF)


func _op_daa() -> void:
	var correction: int = 0
	var carry: bool = flag_CY
	if (A & 0x0F) > 9 or flag_AC:
		correction += 0x06
	if ((A >> 4) & 0x0F) > 9 or flag_CY or (((A >> 4) & 0x0F) == 9 and (A & 0x0F) > 9):
		correction += 0x60
		carry = true
	flag_AC = ((A & 0x0F) + (correction & 0x0F)) > 0x0F
	A = (A + correction) & 0xFF
	flag_CY = carry
	_update_szp(A)


func _op_rlc() -> void:
	var carry: bool = (A & 0x80) != 0
	A = ((A << 1) | int(carry)) & 0xFF
	flag_CY = carry


func _op_rrc() -> void:
	var carry: bool = (A & 0x01) != 0
	A = ((A >> 1) | (int(carry) << 7)) & 0xFF
	flag_CY = carry


func _op_ral() -> void:
	var carry: bool = (A & 0x80) != 0
	A = ((A << 1) | int(flag_CY)) & 0xFF
	flag_CY = carry


func _op_rar() -> void:
	var carry: bool = (A & 0x01) != 0
	A = ((A >> 1) | (int(flag_CY) << 7)) & 0xFF
	flag_CY = carry


# Fetch / decode / execute. Returns T-states taken.


func step() -> int:
	if halted:
		return 0

	var opcode: int = read_byte(PC)
	var instr_start: int = PC
	PC = (PC + 1) & 0xFFFF

	if opcode == 0x00: return 4 # NOP
	if opcode == 0x76: halted = true; return 5 # HLT
	if opcode == 0x07: _op_rlc(); return 4
	if opcode == 0x0F: _op_rrc(); return 4
	if opcode == 0x17: _op_ral(); return 4
	if opcode == 0x1F: _op_rar(); return 4
	if opcode == 0x27: _op_daa(); return 4
	if opcode == 0x2F: A = (~A) & 0xFF; return 4 # CMA
	if opcode == 0x37: flag_CY = true; return 4 # STC
	if opcode == 0x3F: flag_CY = not flag_CY; return 4 # CMC
	if opcode == 0xC3: PC = _imm16(); return 10 # JMP
	if opcode == 0xCD: _call(_imm16()); return 18 # CALL
	if opcode == 0xC9: PC = _pop16(); return 10 # RET
	if opcode == 0x22: # SHLD addr
		var addr: int = _imm16()
		write_byte(addr, L)
		write_byte((addr + 1) & 0xFFFF, H)
		return 16
	if opcode == 0x2A: # LHLD addr
		var addr: int = _imm16()
		L = read_byte(addr)
		H = read_byte((addr + 1) & 0xFFFF)
		return 16
	if opcode == 0x32: write_byte(_imm16(), A); return 13 # STA
	if opcode == 0x3A: A = read_byte(_imm16()); return 13 # LDA
	if opcode == 0xEB: # XCHG
		var t: int = H; H = D; D = t
		t = L; L = E; E = t
		return 4
	if opcode == 0xE3: # XTHL
		var lo: int = read_byte(SP)
		var hi: int = read_byte((SP + 1) & 0xFFFF)
		write_byte(SP, L)
		write_byte((SP + 1) & 0xFFFF, H)
		L = lo; H = hi
		return 16
	if opcode == 0xF9: SP = (H << 8) | L; return 6 # SPHL
	if opcode == 0xE9: PC = (H << 8) | L; return 6 # PCHL
	if opcode == 0xF3: interrupts_enabled = false; return 4 # DI
	if opcode == 0xFB: interrupts_enabled = true; return 4 # EI
	if opcode == 0xDB: # IN port
		var port: int = read_byte(PC); PC = (PC + 1) & 0xFFFF
		A = input_ports[port]
		return 10
	if opcode == 0xD3: # OUT port
		var port: int = read_byte(PC); PC = (PC + 1) & 0xFFFF
		output_ports[port] = A & 0xFF
		return 10
	if opcode == 0x02 or opcode == 0x12: # STAX B/D
		write_byte(_get_rp((opcode >> 4) & 1), A)
		return 7
	if opcode == 0x0A or opcode == 0x1A: # LDAX B/D
		A = read_byte(_get_rp((opcode >> 4) & 1))
		return 7

	#grouped opcode patterns 
	if (opcode & 0xC0) == 0x40: # MOV d, s
		var d: int = (opcode >> 3) & 7
		var s: int = opcode & 7
		_set_r(d, _get_r(s))
		return 7 if (d == 6 or s == 6) else 4

	if (opcode & 0xC0) == 0x80: # ADD/ADC/SUB/SBB/ANA/XRA/ORA/CMP  r
		var op: int = (opcode >> 3) & 7
		var r: int = opcode & 7
		var val: int = _get_r(r)
		match op:
			0: _alu_add(val, false)
			1: _alu_add(val, true)
			2: _alu_sub(val, false)
			3: _alu_sub(val, true)
			4: _alu_and(val)
			5: _alu_xor(val)
			6: _alu_or(val)
			7: _alu_cmp(val)
		return 7 if r == 6 else 4

	if (opcode & 0xC7) == 0x06: # MVI r, data
		var r: int = (opcode >> 3) & 7
		var data: int = read_byte(PC); PC = (PC + 1) & 0xFFFF
		_set_r(r, data)
		return 10 if r == 6 else 7

	if (opcode & 0xC7) == 0x04: # INR r
		var r: int = (opcode >> 3) & 7
		var val: int = (_get_r(r) + 1) & 0xFF
		flag_AC = (val & 0x0F) == 0x00
		_set_r(r, val)
		_update_szp(val)
		return 10 if r == 6 else 4

	if (opcode & 0xC7) == 0x05: # DCR r
		var r: int = (opcode >> 3) & 7
		var val: int = (_get_r(r) - 1) & 0xFF
		flag_AC = (val & 0x0F) != 0x0F
		_set_r(r, val)
		_update_szp(val)
		return 10 if r == 6 else 4

	if (opcode & 0xC7) == 0xC6: # ADI/ACI/SUI/SBI/ANI/XRI/ORI/CPI data
		var op: int = (opcode >> 3) & 7
		var data: int = read_byte(PC); PC = (PC + 1) & 0xFFFF
		match op:
			0: _alu_add(data, false)
			1: _alu_add(data, true)
			2: _alu_sub(data, false)
			3: _alu_sub(data, true)
			4: _alu_and(data)
			5: _alu_xor(data)
			6: _alu_or(data)
			7: _alu_cmp(data)
		return 7

	if (opcode & 0xCF) == 0x01: # LXI rp, data16
		_set_rp((opcode >> 4) & 3, _imm16())
		return 10

	if (opcode & 0xCF) == 0x03: # INX rp
		var rp: int = (opcode >> 4) & 3
		_set_rp(rp, (_get_rp(rp) + 1) & 0xFFFF)
		return 6

	if (opcode & 0xCF) == 0x0B: # DCX rp
		var rp: int = (opcode >> 4) & 3
		_set_rp(rp, (_get_rp(rp) - 1) & 0xFFFF)
		return 6

	if (opcode & 0xCF) == 0x09: # DAD rp
		var rp: int = (opcode >> 4) & 3
		var hl: int = (H << 8) | L
		var res: int = hl + _get_rp(rp)
		flag_CY = res > 0xFFFF
		res &= 0xFFFF
		H = (res >> 8) & 0xFF
		L = res & 0xFF
		return 10

	if (opcode & 0xCF) == 0xC5: # PUSH rp
		_push16(_get_rp_push((opcode >> 4) & 3))
		return 12

	if (opcode & 0xCF) == 0xC1: # POP rp
		_set_rp_push((opcode >> 4) & 3, _pop16())
		return 10

	if (opcode & 0xC7) == 0xC7: # RST n
		var n: int = (opcode >> 3) & 7
		_call(n * 8)
		return 12

	if (opcode & 0xC7) == 0xC2: # conditional JMP
		var addr: int = _imm16()
		if _check_condition((opcode >> 3) & 7):
			PC = addr
			return 10
		return 7

	if (opcode & 0xC7) == 0xC4: # conditional CALL
		var addr: int = _imm16()
		if _check_condition((opcode >> 3) & 7):
			_call(addr)
			return 18
		return 9

	if (opcode & 0xC7) == 0xC0: # conditional RET
		if _check_condition((opcode >> 3) & 7):
			PC = _pop16()
			return 12
		return 6

	var length: int = INSTR_LENGTH[opcode]
	PC = (instr_start + length) & 0xFFFF
	push_warning("Unimplemented opcode: 0x%02X at PC: 0x%04X" % [opcode, instr_start])
	return 4



func disassemble_at(addr: int) -> Dictionary:
	var opcode: int = read_byte(addr)
	var b1: int = read_byte((addr + 1) & 0xFFFF)
	var b2: int = read_byte((addr + 2) & 0xFFFF)
	var reg_names := ["B", "C", "D", "E", "H", "L", "M", "A"]
	var rp_names := ["B", "D", "H", "SP"]
	var rp_push_names := ["B", "D", "H", "PSW"]
	var cond_names := ["NZ", "Z", "NC", "C", "PO", "PE", "P", "M"]
	var alu_names := ["ADD", "ADC", "SUB", "SBB", "ANA", "XRA", "ORA", "CMP"]
	var imm_alu_names := ["ADI", "ACI", "SUI", "SBI", "ANI", "XRI", "ORI", "CPI"]

	var text: String = "DB %02Xh" % opcode
	var length: int = 1

	if opcode == 0x00: text = "NOP"
	elif opcode == 0x76: text = "HLT"
	elif opcode == 0x07: text = "RLC"
	elif opcode == 0x0F: text = "RRC"
	elif opcode == 0x17: text = "RAL"
	elif opcode == 0x1F: text = "RAR"
	elif opcode == 0x27: text = "DAA"
	elif opcode == 0x2F: text = "CMA"
	elif opcode == 0x37: text = "STC"
	elif opcode == 0x3F: text = "CMC"
	elif opcode == 0xC3: text = "JMP %04Xh" % ((b2 << 8) | b1); length = 3
	elif opcode == 0xCD: text = "CALL %04Xh" % ((b2 << 8) | b1); length = 3
	elif opcode == 0xC9: text = "RET"
	elif opcode == 0x22: text = "SHLD %04Xh" % ((b2 << 8) | b1); length = 3
	elif opcode == 0x2A: text = "LHLD %04Xh" % ((b2 << 8) | b1); length = 3
	elif opcode == 0x32: text = "STA %04Xh" % ((b2 << 8) | b1); length = 3
	elif opcode == 0x3A: text = "LDA %04Xh" % ((b2 << 8) | b1); length = 3
	elif opcode == 0xEB: text = "XCHG"
	elif opcode == 0xE3: text = "XTHL"
	elif opcode == 0xF9: text = "SPHL"
	elif opcode == 0xE9: text = "PCHL"
	elif opcode == 0xF3: text = "DI"
	elif opcode == 0xFB: text = "EI"
	elif opcode == 0xDB: text = "IN %02Xh" % b1; length = 2
	elif opcode == 0xD3: text = "OUT %02Xh" % b1; length = 2
	elif opcode == 0x02: text = "STAX B"
	elif opcode == 0x12: text = "STAX D"
	elif opcode == 0x0A: text = "LDAX B"
	elif opcode == 0x1A: text = "LDAX D"
	elif (opcode & 0xC0) == 0x40:
		text = "MOV %s,%s" % [reg_names[(opcode >> 3) & 7], reg_names[opcode & 7]]
	elif (opcode & 0xC0) == 0x80:
		text = "%s %s" % [alu_names[(opcode >> 3) & 7], reg_names[opcode & 7]]
	elif (opcode & 0xC7) == 0x06:
		text = "MVI %s,%02Xh" % [reg_names[(opcode >> 3) & 7], b1]; length = 2
	elif (opcode & 0xC7) == 0x04:
		text = "INR %s" % reg_names[(opcode >> 3) & 7]
	elif (opcode & 0xC7) == 0x05:
		text = "DCR %s" % reg_names[(opcode >> 3) & 7]
	elif (opcode & 0xC7) == 0xC6:
		text = "%s %02Xh" % [imm_alu_names[(opcode >> 3) & 7], b1]; length = 2
	elif (opcode & 0xCF) == 0x01:
		text = "LXI %s,%04Xh" % [rp_names[(opcode >> 4) & 3], (b2 << 8) | b1]; length = 3
	elif (opcode & 0xCF) == 0x03:
		text = "INX %s" % rp_names[(opcode >> 4) & 3]
	elif (opcode & 0xCF) == 0x0B:
		text = "DCX %s" % rp_names[(opcode >> 4) & 3]
	elif (opcode & 0xCF) == 0x09:
		text = "DAD %s" % rp_names[(opcode >> 4) & 3]
	elif (opcode & 0xCF) == 0xC5:
		text = "PUSH %s" % rp_push_names[(opcode >> 4) & 3]
	elif (opcode & 0xCF) == 0xC1:
		text = "POP %s" % rp_push_names[(opcode >> 4) & 3]
	elif (opcode & 0xC7) == 0xC7:
		text = "RST %d" % ((opcode >> 3) & 7)
	elif (opcode & 0xC7) == 0xC2:
		text = "J%s %04Xh" % [cond_names[(opcode >> 3) & 7], (b2 << 8) | b1]; length = 3
	elif (opcode & 0xC7) == 0xC4:
		text = "C%s %04Xh" % [cond_names[(opcode >> 3) & 7], (b2 << 8) | b1]; length = 3
	elif (opcode & 0xC7) == 0xC0:
		text = "R%s" % cond_names[(opcode >> 3) & 7]

	return {"length": length, "text": text}
