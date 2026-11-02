"""Generate an interface-only (structural) copy of the AFDX RTL for Quartus RTL Viewer.

Every module keeps its real parameter/port list, its real declarations and its real
sub-module instantiations (plus any generate block that wraps them).  All procedural
logic (always / initial / function / task) and loose assign statements are dropped,
so Quartus only shows blocks and the nets between them.
"""
import io
import os
import re

RTL = r'F:\bigfatfish\AFDX\elinx\rtl'
IP = r'F:\bigfatfish\AFDX\elinx\afdx.srcs\sources_1\ip'
OUT = r'F:\bigfatfish\AFDX\quartus\rtl'

IP_STUBS = [
    ('pll', 'pll/pll.v'),
    ('eth_1', 'eth_1/eth_1.v'),
    ('eth_2', 'eth_2/eth_2.v'),
    ('vl_config_ip', 'vl_config_ip/vl_config_ip.v'),
    ('vl_state_ip', 'vl_state_ip/vl_state_ip.v'),
    ('mib_rx_ip', 'mib_rx_ip/mib_rx_ip.v'),
    ('mib_tx_ip', 'mib_tx_ip/mib_tx_ip.v'),
    ('rx_port_buf_ip', 'rx_port_buf_ip/rx_port_buf_ip.v'),
    ('tx_port_buf_ip', 'tx_port_buf_ip/tx_port_buf_ip.v'),
    ('rx_frame_buf', 'rx_frame_buf/rx_frame_buf.v'),
    ('file_table_ip', 'file_table_ip/file_table_ip.v'),
    ('file_buffer_ip', 'file_buffer_ip/file_buffer_ip.v'),
]

DECL_KW = ('input', 'output', 'inout', 'wire', 'reg', 'integer', 'genvar',
           'localparam', 'parameter', 'signed', 'time')


def strip_comments(text):
    text = re.sub(r'/\*[\s\S]*?\*/', lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text)
    return re.sub(r'//[^\n]*', '', text)


def find_header_end(text, start):
    depth = 0
    seen = False
    i = start
    while i < len(text):
        c = text[i]
        if c == '(':
            depth += 1
            seen = True
        elif c == ')':
            depth -= 1
        elif c == ';' and seen and depth == 0:
            return i + 1
        i += 1
    raise RuntimeError('unterminated module header')


def collect_decl(lines, k):
    """Keep a declaration, swallowing continuation lines up to the ';'."""
    out = [lines[k]]
    i = k
    while lines[i].rstrip().endswith(',') or ';' not in lines[i]:
        i += 1
        if i >= len(lines):
            break
        out.append(lines[i])
    return out, i


def collect_instance(lines, k):
    """Keep one instantiation statement, balancing parentheses."""
    out = []
    depth = 0
    i = k
    started = False
    while i < len(lines):
        ln = lines[i]
        out.append(ln)
        for ch in ln:
            if ch == '(':
                depth += 1
                started = True
            elif ch == ')':
                depth -= 1
        if started and depth <= 0 and ln.rstrip().endswith(';'):
            return out, i
        i += 1
    return out, i


def make_skeleton(path, name, known, is_ip=False):
    raw = strip_comments(io.open(path, encoding='utf-8', errors='replace').read())
    m = re.search(r'\bmodule\s+' + re.escape(name) + r'\b', raw)
    if not m:
        m = re.search(r'\bmodule\s+(\w+)', raw)
        if not m:
            raise RuntimeError('no module in ' + path)
    hend = find_header_end(raw, m.start())
    header = raw[m.start():hend].strip()
    end = raw.rindex('endmodule')
    body_lines = raw[hend:end].split('\n')

    # IP stubs: keep non-ANSI port declarations only
    kept = []
    i = 0
    gen_depth = 0
    if is_ip:
        while i < len(body_lines):
            s = body_lines[i].strip()
            if re.match(r'(input|output|inout)\b', s):
                blk, i = collect_decl(body_lines, i)
                kept.extend(' '.join(x.split()) for x in blk)
                i += 1
                continue
            i += 1
    else:
        while i < len(body_lines):
            s = body_lines[i].strip()
            if s == '':
                i += 1
                continue
            if re.match(r'generate\b', s):
                gen_depth += 1
                kept.append(body_lines[i])
                i += 1
                continue
            if re.match(r'endgenerate\b', s):
                gen_depth = max(0, gen_depth - 1)
                kept.append(body_lines[i])
                i += 1
                continue
            if gen_depth > 0:
                kept.append(body_lines[i])
                i += 1
                continue
            if re.match(r'function\b', s):
                while i < len(body_lines) and not re.search(r'\bendfunction\b', body_lines[i]):
                    i += 1
                i += 1
                continue
            if re.match(r'task\b', s):
                while i < len(body_lines) and not re.search(r'\bendtask\b', body_lines[i]):
                    i += 1
                i += 1
                continue
            if re.match(r'(' + '|'.join(DECL_KW) + r')\b', s):
                blk, i = collect_decl(body_lines, i)
                first = blk[0]
                if len(blk) == 1 and re.match(r'(wire|reg)\b', first.strip()) and '=' in first \
                        and first.rstrip().endswith(';'):
                    head = first.split('=')[0].rstrip() + ';'
                    kept.append(head)
                else:
                    kept.extend(blk)
                i += 1
                continue
            mi = re.match(r'(\w+)\s*(#\s*\(|(\w+)\s*\()', s)
            if mi and mi.group(1) in known:
                blk, i = collect_instance(body_lines, i)
                kept.extend(blk)
                i += 1
                continue
            i += 1

    text = '\n'.join(kept)
    text = re.sub(r'\n{3,}', '\n\n', text).strip()
    if is_ip:
        note = ('// %s : vendor IP stub for Quartus RTL Viewer\n'
                '// Port list copied from the real IP wrapper; body intentionally empty.' % name)
    else:
        note = ('// %s : interface-only skeleton for Quartus RTL Viewer\n'
                '// Real parameters/ports + real sub-module instantiations only;\n'
                '// all procedural logic and loose assign statements have been removed on purpose.' % name)
    return note + '\n' + header + '\n' + text + '\n\nendmodule\n'


def main():
    os.makedirs(OUT, exist_ok=True)
    known = set()
    for fn in os.listdir(RTL):
        if fn.endswith('.v'):
            known.add(fn[:-2])
    known.update(n for n, _ in IP_STUBS)

    count = 0
    for fn in sorted(os.listdir(RTL)):
        if not fn.endswith('.v'):
            continue
        text = make_skeleton(os.path.join(RTL, fn), fn[:-2], known)
        io.open(os.path.join(OUT, fn), 'w', encoding='utf-8', newline='\n').write(text)
        count += 1
    for name, rel in IP_STUBS:
        text = make_skeleton(os.path.join(IP, rel), name, known, is_ip=True)
        io.open(os.path.join(OUT, name + '.v'), 'w', encoding='utf-8', newline='\n').write(text)
        count += 1
    print('generated', count, 'files into', OUT)


if __name__ == '__main__':
    main()
