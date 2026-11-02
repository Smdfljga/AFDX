import io, os, re

BASE = r'F:\bigfatfish\AFDX\quartus'
RTLD = os.path.join(BASE, 'rtl')
files = sorted(f for f in os.listdir(RTLD) if f.endswith('.v'))

# top first is not required by Quartus, but keep a deterministic order with top.v last
order = [f for f in files if f != 'top.v'] + [f for f in files if f == 'top.v']

qsf = []
qsf.append('# Quartus project for RTL Viewer only: interface + instantiation skeleton of the AFDX design.')
qsf.append('# No behaviour is implemented - open RTL Viewer after Analysis & Synthesis.')
qsf.append('')
qsf.append('set_global_assignment -name FAMILY "Cyclone IV E"')
qsf.append('set_global_assignment -name DEVICE EP4CE115F29C7')
qsf.append('set_global_assignment -name TOP_LEVEL_ENTITY top')
qsf.append('set_global_assignment -name ORIGINAL_QUARTUS_VERSION 20.1.1')
qsf.append('set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files')
qsf.append('')
for f in order:
    qsf.append('set_global_assignment -name VERILOG_FILE rtl/%s' % f)
qsf.append('')
io.open(os.path.join(BASE, 'afdx_rtlview.qsf'), 'w', encoding='utf-8', newline='\n').write('\n'.join(qsf))

qpf = '''<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<Project version="1">
  <Version Version="20.1.1 Build 720 11/25/2020 SJ Standard Edition" />
  <Paths>
    <Path>.</Path>
  </Paths>
</Project>
'''
io.open(os.path.join(BASE, 'afdx_rtlview.qpf'), 'w', encoding='utf-8', newline='\n').write(qpf)
print('qsf files:', len(order), ' -> ', os.path.join(BASE, 'afdx_rtlview.qsf'))
