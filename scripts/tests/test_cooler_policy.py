#!/usr/bin/env python3
"""The cooler profile must not replace the Flip5's safety or calibration data."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('cooler', ROOT / 'scripts/prepare_cooler_policy.py')
cooler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cooler)


class CoolerPolicyTest(unittest.TestCase):
    def setUp(self):
        self.stock = ET.fromstring('''<siop_document>
          <overheatcontrol><complex><EMR formula="SKIN" temp="470"/>
            <SS formula="SKIN*BAT" temp="550.470"/></complex></overheatcontrol>
          <modelsettings><Skin type="LRP2"/><sensors><custom value="keep"/></sensors></modelsettings>
          <components>
            <component name="AP" tempType="SKIN"><limiter name="CPUFreqMax" temp="360:390:410:440"/>
              <limiter name="GPUFreqMax" temp="360:390:410:440"/>
              <limiter name="OverLimit" value="2092800:1977600:-1"/>
              <limiter name="JobRestriction" temp="360" value="-1:1"/></component>
            <component name="CP" tempType="SKIN"><limiter name="CpLowMode" temp="340:360:415:440"/>
              <limiter name="CpLowMode" temp="415:440" region="China"/>
              <limiter name="SADisable" temp="430:450" value="-1:1"/>
              <limiter name="SCellDropNSA" temp="420:425" value="-1:1"/></component>
            <component name="CP" tempType="SKIN" region="JP"><limiter name="SADisable" temp="420:440"/></component>
            <component name="DISPLAY" tempType="SKIN"><limiter name="Brightness" temp="399:400:420:450:470"/></component>
          </components>
          <scenarios><scenario name="DefaultLowHeatMode" tempType="SKIN">
            <limiter name="CPUFreqMax"/><limiter name="GPUFreqMax"/><limiter name="OverLimit"/>
          </scenario><scenario name="LowTemp" tempType="BAT"><limiter name="Charging" value="-1"/></scenario>
          <scenario name="CameraControl"><limiter name="CameraFps" temp="320:340:370:390"/></scenario></scenarios>
        </siop_document>''')
        for name in ('SIPStart', 'AppStart', 'Badge', 'CallStart', 'WakeUp'):
            scenario = ET.SubElement(self.stock.find('scenarios'), 'scenario', name=name, tempType='SKIN')
            ET.SubElement(scenario, 'limiter', name='CPUFreqMax', temp='370:390', value='-1:2092800')
        self.fold = deepcopy(self.stock)
        for parent in [self.fold.find("components/component[@name='AP']"),
                       self.fold.find("scenarios/scenario[@name='DefaultLowHeatMode']")]:
            for limiter in parent:
                if limiter.get('name') != 'JobRestriction':
                    limiter.set('temp', '380:400:420:450')
        for name in ('SIPStart', 'AppStart', 'Badge', 'CallStart', 'WakeUp'):
            self.fold.find(f"scenarios/scenario[@name='{name}']/limiter").set('value', '-1:2841600')
        self.default = ET.fromstring('''<siop_document><components><component name="DISPLAY">
          <limiter name="AppCastDisable" temp="450:470:500" value="-1:1:1" delay="0:300:0"/>
          <limiter name="MultiWindow" temp="450:470:500" value="-1:1:1" delay="0:300:0"/>
        </component></components><scenarios>
          <scenario name="Dex" tempType="SKIN"><limiter name="LimitHrr" temp="430" value="-1:1"/>
            <limiter name="DynamicFpsLevel" temp="430" value="-1:30"/></scenario>
          <scenario name="MultiWindow" tempType="SKIN"><limiter name="LimitHrr" temp="430" value="-1:1"/></scenario>
        </scenarios></siop_document>''')

    def test_preserves_safety_sensor_calibration_and_unrelated_limits(self):
        before = ET.tostring(self.stock)
        policy = cooler.cooler_policy(self.stock, self.fold, self.default)
        for path in ['overheatcontrol', 'modelsettings', "scenarios/scenario[@name='LowTemp']",
                     "scenarios/scenario[@name='CameraControl']", "components/component[@region='JP']",
                     "components/component[@name='CP']/limiter[@region='China']",
                     "components/component[@name='DISPLAY']/limiter[@name='Brightness']"]:
            with self.subTest(path=path):
                self.assertEqual(ET.tostring(policy.find(path)), ET.tostring(self.stock.find(path)))
        self.assertEqual(ET.tostring(self.stock), before)

    def test_delays_early_limits_below_emergency_without_disabling_them(self):
        policy = cooler.cooler_policy(self.stock, self.fold, self.default)
        dex = policy.find("scenarios/scenario[@name='Dex']/limiter[@name='DynamicFpsLevel']")
        self.assertEqual(dex.attrib, {'name': 'DynamicFpsLevel', 'temp': '460', 'value': '-1:30'})
        radio = policy.find("components/component[@name='CP']/limiter[@name='SADisable']")
        self.assertEqual(radio.get('temp'), '450:460')
        self.assertEqual(radio.get('value'), '-1:1')
        ap = policy.find("components/component[@name='AP']/limiter[@name='CPUFreqMax']")
        self.assertEqual(ET.tostring(ap), ET.tostring(self.fold.find("components/component[@name='AP']/limiter[@name='CPUFreqMax']")))
        launch = policy.find("scenarios/scenario[@name='AppStart']/limiter[@name='CPUFreqMax']")
        self.assertEqual(launch.get('value'), '-1:2841600')

    def test_unknown_donor_fails_before_writing_a_policy(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / 'siop_default.xml').write_text('<siop_document/>')
            output = source / 'assets/onigiri-cooler.xml'
            with self.assertRaisesRegex(ValueError, 'Unsupported Samsung thermal table'):
                cooler.main(source, output)
            self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
