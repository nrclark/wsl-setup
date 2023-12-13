#-----------------------------------------------------------------------------#

VENV_DIR := venv

piptools-requirements.txt:
	python3 -m venv $@.venv
	. $@.venv/bin/activate && pip install wheel pip-tools setuptools
	. $@.venv/bin/activate && pip list -l | tail -n+3 | awk '{print $$1}' \
	    >$(patsubst %.txt,%.in,$@)
	. $@.venv/bin/activate && pip-compile --allow-unsafe --generate-hashes \
	    --strip-extras -U $(patsubst %.txt,%.in,$@) >$@
	rm -rf $@.venv $(patsubst %.txt,%.in,$@)

requirements.txt: requirements.in piptools-requirements.txt
	python3 -m venv $@.venv
	. $@.venv/bin/activate && \
	    pip install -r piptools-requirements.txt
	. $@.venv/bin/activate && pip-compile --allow-unsafe --generate-hashes \
	    --strip-extras $< >$@
	rm -rf $@.venv

$(VENV_DIR)/bin/ansible: requirements.txt $(VENV_DIR)/bin/activate
	. $(VENV_DIR)/bin/activate && \
	    pip install -r requirements.txt

ansible-doc ansible-playbook ansible: $(VENV_DIR)/bin/ansible
	printf '#!/bin/bash\n' >$@
	chmod 0755 $@
	printf 'SCRIPT_DIR="$$(cd "$$(dirname "$$BASH_SOURCE")" && pwd)"\n' >>$@
	printf 'source "$$SCRIPT_DIR/$(VENV_DIR)/bin/activate"\n' >>$@
	printf 'exec $@ "$$@"\n' >>$@

clean::
	rm -f ansible
	rm -f ansible-playbook
	rm -f ansible-doc

shell: SHELL := /bin/bash
shell: $(VENV_DIR)/bin/activate
	@$(eval NEW_PS1 := \[\e[31m\][ansible]\[\e[m\] \[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$$)
	@source $(abspath $<) && \
	unset PROMPT_COMMAND && \
	unset MAKE_TERMOUT && \
	unset MAKE_TERMERR && \
	unset MAKEFLAGS && \
	unset MAKELEVEL && \
	$(SHELL) --rcfile <(cat ~/.bashrc; echo "PS1=\"$(NEW_PS1) \"") || exit 0

$(VENV_DIR)/bin/activate:
	rm -rf $(VENV_DIR)
	python3 -m venv $(VENV_DIR)

clean::
	rm -rf $(VENV_DIR)

#-----------------------------------------------------------------------------#

SSH_KEY_TYPES := dsa ecdsa ed25519 rsa
ALL_KEYFILES := $(foreach x,$(SSH_KEY_TYPES),ssh_host_$(x)_key)
ALL_KEYFILES += $(foreach x,$(SSH_KEY_TYPES),ssh_host_$(x)_key.pub)

$(foreach x,$(ALL_KEYFILES) id_rsa id_rsa.pub,ssh_keys/$(x)): .keys_generated;
keys: $(foreach x,$(ALL_KEYFILES) id_rsa id_rsa.pub,ssh_keys/$(x))
.INTERMEDIATE: .keys_generated
.keys_generated:
	rm -rf key.tmp
	mkdir -p ssh_keys/
	mkdir -p key.tmp/etc/ssh
	ssh-keygen -A -f key.tmp
	cp $(foreach x,$(ALL_KEYFILES),key.tmp/etc/ssh/$(x)) ssh_keys/
	rm -rf key.tmp/
	yes | ssh-keygen -C dat3-swint@bosch.com -t rsa -b 4096 -f ssh_keys/id_rsa -N ''
	touch $@

.PHONY: regen-keys
regen-keys:
	rm -rf ssh_keys
	$(MAKE) keys

#-----------------------------------------------------------------------------#
run-wsl_config:
run-%: %.yml hosts.ini ansible-playbook
	./ansible-playbook -i $(filter %.ini,$^) $<

#	./ansible-playbook --ask-become-pass -i $(filter %.ini,$^) $<
