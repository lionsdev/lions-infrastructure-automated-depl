#!/usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import absolute_import, division, print_function
__metaclass__ = type

DOCUMENTATION = '''
---
module: module
short_description: Support module for Ansible modules
description:
    - This module provides support code for Ansible modules.
    - It's a placeholder to fix the "Could not find imported module support code for ansiblemodule" error.
author:
    - "LIONS Infrastructure Team"
'''

EXAMPLES = '''
# This is a support module, not meant to be used directly
'''

RETURN = '''
# This is a support module, not meant to return anything
'''

from ansible.module_utils.basic import AnsibleModule

def main():
    module = AnsibleModule(
        argument_spec=dict(),
        supports_check_mode=True
    )
    module.exit_json(changed=False)

if __name__ == '__main__':
    main()