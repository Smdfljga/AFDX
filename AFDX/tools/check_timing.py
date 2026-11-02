"""读取 eLinx 布局布线后的时序数据库，按时钟域打印 setup/hold/recovery 结果。

用法：
    python AFDX\\tools\\check_timing.py [afdx.tan.pb 路径]

默认读取 AFDX\\elinx\\afdx.runs\\imple_1\\afdx.tan.pb。每次重新布局布线后都会重写这个
数据库，所以重跑 PnR 后直接再执行一次即可对比（尤其用来确认 p0_rxc_a/b 域的
recovery 失败端点是否已经因为 afdx.edc 的 false_path 而消失）。
"""
import os
import sqlite3
import sys

DEFAULT_DB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          'elinx', 'afdx.runs', 'imple_1', 'afdx.tan.pb')
# 这里只关心 intra-clock 表：跨时钟域路径在 afdx.edc 里已经全部按异步处理
CHECKS = (
    ('setup', 'elinx_intra_clock_summary', 'setup_worst_slack', 'setup_fail_ends', 'setup_total_ends'),
    ('hold', 'elinx_intra_clock_summary', 'hold_worst_slack', 'hold_fail_ends', 'hold_total_ends'),
    ('recovery', 'elinx_intra_clock_summary', 'recovery_worst_slack', 'recovery_fail_ends', 'recovery_total_ends'),
    ('removal', 'elinx_intra_clock_summary', 'removal_worst_slack', 'removal_fail_ends', 'removal_total_ends'),
)


def load(path):
    if not os.path.exists(path):
        sys.exit('找不到时序数据库：%s' % path)
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    return conn


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DB
    conn = load(path)
    print('数据库：%s' % path)
    print('修改时间：%s' % __import__('datetime').datetime.fromtimestamp(os.path.getmtime(path)))
    print()
    rows = list(conn.execute('select * from elinx_intra_clock_summary'))
    # ps 转成 ns 便于和报告对照
    for label, table, worst_col, fail_col, total_col in CHECKS:
        print('=== %s ===' % label)
        for r in rows:
            worst = r[worst_col] / 1000.0 if r[worst_col] is not None else 0.0
            if worst == 0.0 and r[fail_col] == 0:
                continue
            print('  %-10s period=%6.1f ns  worst=%+8.3f ns  fail=%4d / %4d' % (
                r['name'], (r['period'] or 0) / 1000.0, worst, r[fail_col], r[total_col]))
        print()
    print('=== Fmax ===')
    for r in rows:
        if r['fmax']:
            print('  %-10s %8.2f MHz  (约束 %6.1f ns)' % (r['name'], r['fmax'], (r['period'] or 0) / 1000.0))
    print()
    # 失败路径归属：确认违例落在厂商 MAC 还是自己的 RTL
    fails = list(conn.execute('select source_clock_id, from_cell_name, to_cell_name '
                              'from elinx_intra_clock_longest_sync_path_report where slack < 0'))
    print('=== setup 失败路径归属（共 %d 条）===' % len(fails))

    def owner(name):
        n = (name or '').replace('\\', '')
        if n.startswith('u_eth_1'):
            return '厂商 MAC #1'
        if n.startswith('u_eth_2'):
            return '厂商 MAC #2'
        if n.startswith('u_afdx') or n.startswith('u_snmp') or n.startswith('u_data') or n.startswith('u_rtc'):
            return '自研 RTL'
        if 'padio' in n or '~I' in n:
            return 'IO 引脚'
        return n.split('|')[0] or '未知'

    group = {}
    for r in fails:
        key = '%s -> %s' % (owner(r['from_cell_name']), owner(r['to_cell_name']))
        group[key] = group.get(key, 0) + 1
    for key in sorted(group, key=lambda k: -group[k]):
        print('  %-26s %d' % (key, group[key]))
    if not group:
        print('  无 setup 违例')


if __name__ == '__main__':
    main()
