extends Control

enum State { IDLE, ENTERING_ADDR, EDITING_DATA, EXAMINING_REG, ENTERING_EXEC_ADDR, RUNNING }

var cpu: CPU8085 = CPU8085.new()
var current_state: State = State.IDLE
var blink_tween: Tween
var active_addr: int = 0x2000
var addr_buffer: String = ""
var data_buffer: String = ""
var exec_addr_buffer: String = ""

const REG_ORDER: Array[String] = ["PC", "SP", "A", "B", "C", "D", "E", "H", "L", "F"]
var reg_index: int = 0
var reg_input_buffer: String = ""

@onready var label_addr: Label = %AddrDisplay
@onready var label_data: Label = %DataDisplay
@onready var keypad: GridContainer = %KeysContainer
@onready var disasm_view: RichTextLabel = %DisassemblyView


func _ready() -> void:
	for child in keypad.get_children():
		if child is Button and child.text.is_valid_hex_number(false) and child.text.length() == 1:
			child.pressed.connect(func(): press_hex(child.text))
	update_displays()


func update_displays() -> void:
	match current_state:
		State.IDLE:
			label_addr.text = "0000"
			label_data.text = "00"

		State.ENTERING_ADDR:
			label_addr.text = addr_buffer.lpad(4, "-")
			label_data.text = "--"

		State.EDITING_DATA:
			label_addr.text = "%04X" % active_addr
			if data_buffer.is_empty():
				label_data.text = "%02X" % cpu.read_byte(active_addr)
			else:
				label_data.text = data_buffer.lpad(2, "-")

		State.EXAMINING_REG:
			var reg_name: String = REG_ORDER[reg_index]
			var width: int = 4 if (reg_name == "PC" or reg_name == "SP") else 2
			label_addr.text = reg_name.lpad(4, " ")
			if reg_input_buffer.is_empty():
				label_data.text = _format_hex(cpu.get_register(reg_name), width)
			else:
				label_data.text = reg_input_buffer.lpad(width, "-")

		State.RUNNING:
			label_addr.text = "RUN "
			label_data.text = "--"
			
		State.ENTERING_EXEC_ADDR:
			label_addr.text = exec_addr_buffer.lpad(4, "-")
			label_data.text = "GO"
	_refresh_disassembly_view()


func _format_hex(val: int, width: int) -> String:
	return ("%0" + str(width) + "X") % val

# Keypad 0-F input
func press_hex(val: String) -> void:
	match current_state:
		State.ENTERING_ADDR:
			if addr_buffer.length() < 4:
				addr_buffer += val
				if addr_buffer.length() == 4:
					active_addr = ("0x" + addr_buffer).hex_to_int()
					current_state = State.EDITING_DATA
					data_buffer = ""
			update_displays()

		State.EDITING_DATA:
			if data_buffer.length() < 2:
				data_buffer += val
				if data_buffer.length() == 2:
					cpu.write_byte(active_addr, ("0x" + data_buffer).hex_to_int())
			update_displays()
			
		State.ENTERING_EXEC_ADDR:
			if exec_addr_buffer.length() < 4:
				exec_addr_buffer += val
			update_displays()

		State.EXAMINING_REG:
			var reg_name: String = REG_ORDER[reg_index]
			var width: int = 4 if (reg_name == "PC" or reg_name == "SP") else 2
			if reg_input_buffer.length() < width:
				reg_input_buffer += val
				if reg_input_buffer.length() == width:
					cpu.set_register(reg_name, ("0x" + reg_input_buffer).hex_to_int())
			update_displays()

		State.IDLE, State.RUNNING:
			pass


func press_exam_mem() -> void:
	current_state = State.ENTERING_ADDR
	addr_buffer = ""
	data_buffer = ""
	update_displays()


func press_exam_reg() -> void:
	current_state = State.EXAMINING_REG
	reg_index = 0
	reg_input_buffer = ""
	update_displays()

func press_next() -> void:
	if current_state == State.ENTERING_ADDR and addr_buffer.length() > 0:
		active_addr = ("0x" + addr_buffer.lpad(4, "0")).hex_to_int()
		current_state = State.EDITING_DATA
		data_buffer = ""

	elif current_state == State.EDITING_DATA or current_state == State.IDLE:
		if data_buffer.length() > 0:
			cpu.write_byte(active_addr, ("0x" + data_buffer).hex_to_int())
			data_buffer = ""
		active_addr = (active_addr + 1) & 0xFFFF
		current_state = State.EDITING_DATA

	elif current_state == State.EXAMINING_REG:
		if reg_input_buffer.length() > 0:
			var reg_name: String = REG_ORDER[reg_index]
			var width: int = 4 if (reg_name == "PC" or reg_name == "SP") else 2
			cpu.set_register(reg_name, ("0x" + reg_input_buffer.lpad(width, "0")).hex_to_int())
		reg_index = (reg_index + 1) % REG_ORDER.size()
		reg_input_buffer = ""

	update_displays()

func press_prev() -> void:
	if current_state == State.ENTERING_ADDR and addr_buffer.length() > 0:
		active_addr = ("0x" + addr_buffer.lpad(4, "0")).hex_to_int()
		current_state = State.EDITING_DATA
		data_buffer = ""

	elif current_state == State.EDITING_DATA or current_state == State.IDLE:
		if data_buffer.length() > 0:
			cpu.write_byte(active_addr, ("0x" + data_buffer).hex_to_int())
			data_buffer = ""
		active_addr = (active_addr - 1) & 0xFFFF
		current_state = State.EDITING_DATA

	elif current_state == State.EXAMINING_REG:
		if reg_input_buffer.length() > 0:
			var reg_name: String = REG_ORDER[reg_index]
			var width: int = 4 if (reg_name == "PC" or reg_name == "SP") else 2
			cpu.set_register(reg_name, ("0x" + reg_input_buffer.lpad(width, "0")).hex_to_int())
		reg_index = (reg_index - 1 + REG_ORDER.size()) % REG_ORDER.size()
		reg_input_buffer = ""

	update_displays()


func press_step() -> void:
	if not cpu.halted:
		cpu.step()
		active_addr = cpu.PC
		current_state = State.IDLE
		update_displays()

func press_go() -> void:
	current_state = State.ENTERING_EXEC_ADDR
	exec_addr_buffer = ""
	update_displays()


func press_exec() -> void:
	if current_state != State.ENTERING_EXEC_ADDR:
		return

	var start_addr: int = ("0x" + exec_addr_buffer.lpad(4, "0")).hex_to_int()
	cpu.PC = start_addr
	cpu.halted = false
	current_state = State.RUNNING
	update_displays()
	await get_tree().process_frame

	var max_instructions := 10000
	while not cpu.halted and max_instructions > 0:
		cpu.step()
		max_instructions -= 1
		if max_instructions % 200 == 0:
			await get_tree().process_frame

	current_state = State.IDLE
	active_addr = cpu.PC
	update_displays()


func press_reset() -> void:
	cpu.reset()
	current_state = State.IDLE
	active_addr = 0x2000
	addr_buffer = ""
	data_buffer = ""
	reg_index = 0
	reg_input_buffer = ""
	exec_addr_buffer = ""
	update_displays()
	_blink_displays()


func _colorize_mnemonic(text: String) -> String:
	var space_idx: int = text.find(" ")
	var mnemonic: String = text
	var operands: String = ""
	if space_idx != -1:
		mnemonic = text.substr(0, space_idx)
		operands = text.substr(space_idx + 1)

	var out: String = "[color=#569CD6]%s[/color]" % mnemonic

	if operands.is_empty():
		return out

	out += " "
	var known_regs := ["A", "B", "C", "D", "E", "H", "L", "M", "SP", "PC", "PSW",
			"NZ", "Z", "NC", "PO", "PE", "P"]
	var parts: PackedStringArray = operands.split(",")
	for i in range(parts.size()):
		var token: String = parts[i].strip_edges()
		var colored: String
		if token.ends_with("h") and token.substr(0, token.length() - 1).is_valid_hex_number(false):
			colored = "[color=#B5CEA8]%s[/color]" % token
		elif token in known_regs:
			colored = "[color=#9CDCFE]%s[/color]" % token 
		else:
			colored = token
		out += colored
		if i < parts.size() - 1:
			out += ","
	return out
	
func _refresh_disassembly_view() -> void:
	var addr: int = cpu.PC
	var max_lines := 30
	var lines_shown := 0

	var lines: Array[String] = []
	while lines_shown < max_lines:
		if not cpu.is_written(addr):
			break
		var info: Dictionary = cpu.disassemble_at(addr)
		var length: int = info.length

		for b in range(length):
			if lines_shown >= max_lines:
				break
			var byte_addr: int = (addr + b) & 0xFFFF
			var byte_val: int = cpu.read_byte(byte_addr)
			var addr_cell: String = "[color=#858585]%04X[/color]" % byte_addr
			var marker: String = "[color=#FFD700]>[/color] " if byte_addr == cpu.PC else "  "

			if b == 0:

				var byte_cell: String = "[color=#6A9955]%02X[/color]" % byte_val
				var text_cell: String = _colorize_mnemonic(info.text)
				var length_label: String = "%dB" % length
				var length_cell: String = "[color=#666666][%s][/color]" % length_label
				lines.append("%s%s %s %s %s" % [marker, addr_cell, byte_cell, text_cell, length_cell])
			else:
				var byte_cell: String = "[color=#6A9955]%02X[/color]" % byte_val
				lines.append("%s%s %s" % [marker, addr_cell, byte_cell])

			lines_shown += 1

		addr = (addr + length) & 0xFFFF

	if lines.is_empty():
		disasm_view.text = "..."
	else:
		disasm_view.text = "\n".join(lines)


func _on_reload_btn_pressed() -> void:
	get_tree().reload_current_scene()


func _blink_displays() -> void:
	if blink_tween:
		blink_tween.kill() 
	label_addr.modulate.a = 0.0
	label_data.modulate.a = 0.0
	blink_tween = create_tween()
	blink_tween.tween_interval(0.08)  
	blink_tween.tween_callback(func():
		label_addr.modulate.a = 1.0
		label_data.modulate.a = 1.0)
