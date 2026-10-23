#!/usr/bin/env python3
"""Build the opt-in cooler policy from the pinned Samsung donor tables."""
from copy import deepcopy
import hashlib
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

HASHES = {
    'siop_default.xml': '733933fb8dfaabdfaa1f4c6b29f00452cb8d743a0497b7413a97828c64a1f432',
    'siop_b5q_sm8550.xml': '86e8c61479538a5e78d945b735b5ce1a63f0e3970a0eb3f35d5e6ad8540ef400',
    'siop_q5q_sm8550.xml': '9ea15e8353eaf098048493ce874f9790254df976e0c914ad9d483ee95eb132c8',
}


def cooler_policy(stock, fold, default):
    policy = deepcopy(stock)
    # Keep the Flip5's LRP2 model and all overheat/battery rules. Only borrow AP limits.
    for path in ("components/component[@name='AP']",
                 "scenarios/scenario[@name='DefaultLowHeatMode']"):
        target, donor = policy.find(path), fold.find(path)
        for name in ('CPUFreqMax', 'GPUFreqMax', 'OverLimit'):
            limiter = target.find(f"limiter[@name='{name}']")
            replacement = deepcopy(donor.find(f"limiter[@name='{name}']"))
            target.remove(limiter)
            target.append(replacement)

    for name in ('SIPStart', 'AppStart', 'Badge', 'CallStart', 'WakeUp'):
        path = f"scenarios/scenario[@name='{name}']"
        target = policy.find(path)
        limiter = target.find("limiter[@name='CPUFreqMax']")
        target.remove(limiter)
        target.append(deepcopy(fold.find(path + "/limiter[@name='CPUFreqMax']")))

    # Regional radio rules remain stock; this ROM targets the XXV Flip5 firmware.
    cp = policy.find("components/component[@name='CP']")
    for limiter in cp:
        if 'region' in limiter.attrib:
            continue
        if limiter.get('name') == 'CpLowMode':
            limiter.set('temp', '340:360:450:460')
        elif limiter.get('name') in ('SCellDropNSA', 'SCellDropSA', 'SADisable', 'LteCCDrop'):
            limiter.set('temp', '450:460')

    display = policy.find("components/component[@name='DISPLAY']")
    for name in ('AppCastDisable', 'MultiWindow'):
        limiter = deepcopy(default.find(f"components/component[@name='DISPLAY']/limiter[@name='{name}']"))
        limiter.set('temp', '460:470:500')
        display.append(limiter)

    for name in ('Dex', 'MultiWindow'):
        scenario = deepcopy(default.find(f"scenarios/scenario[@name='{name}']"))
        for limiter in scenario:
            limiter.set('temp', '460')
        policy.find('scenarios').append(scenario)

    if ET.tostring(policy.find('overheatcontrol')) != ET.tostring(stock.find('overheatcontrol')):
        raise ValueError('Cooler profile changed emergency protection')
    if ET.tostring(policy.find('modelsettings')) != ET.tostring(stock.find('modelsettings')):
        raise ValueError('Cooler profile changed sensor calibration')
    return policy


def main(source, output):
    tables = {}
    for name, expected in HASHES.items():
        data = (source / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError(f'Unsupported Samsung thermal table: {name}')
        tables[name] = ET.fromstring(data)
    policy = cooler_policy(tables['siop_b5q_sm8550.xml'], tables['siop_q5q_sm8550.xml'],
                           tables['siop_default.xml'])
    ET.indent(policy)
    output.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(policy).write(output, encoding='utf-8', xml_declaration=True)


if __name__ == '__main__':
    main(Path(sys.argv[1]), Path(sys.argv[2]))
