with open(r'C:\Users\drago\Desktop\projects\Durrah care mob app\mc_mod_front\src\features\pilgrims\pages\pilgrim-provisioning-page.tsx', 'r', encoding='utf-8') as f:
    text = f.read()

import re
match = re.search(r'selectedProvisioningItem\.one_time_login\.token', text)
if match:
    print('Found token in dialog')
else:
    print('Not found')
