#-----------------------------------------------------------------------------#

VENV_DIR := venv

ansible-requirements.txt: | $(VENV_DIR)/bin/activate
	. $< && pip install wheel
	. $< && pip install ansible
	. $< && pip list --outdated --format=freeze | grep -v '^\-e' | \
	    cut -d = -f 1 | xargs -n1 pip install --upgrade
	. $< && pip freeze >$@

$(VENV_DIR)/bin/ansible: ansible-requirements.txt
	. $(VENV_DIR)/bin/activate && \
	    pip install -r ansible-requirements.txt

ansible-playbook ansible: $(VENV_DIR)/bin/ansible
	printf '#!/bin/bash\n' >$@
	chmod 0755 $@
	printf 'SCRIPT_DIR="$$(cd "$$(dirname "$$BASH_SOURCE")" && pwd)"\n' >>$@
	printf 'source "$$SCRIPT_DIR/venv/bin/activate"\n' >>$@
	printf 'exec $@ "$$@"\n' >>$@

clean::
	rm -f ansible
	rm -f ansible-playbook

ansible-shell: SHELL := /bin/bash
ansible-shell: $(VENV_DIR)/bin/activate
	@$(eval NEW_PS1 := \[\e[31m\][ansible]\[\e[m\] \[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$$)
	@source $(abspath $<) && \
	unset PROMPT_COMMAND && \
	unset MAKE_TERMOUT && \
	unset MAKE_TERMERR && \
	unset MAKEFLAGS && \
	unset MAKELEVEL && \
	$(SHELL) --rcfile <(cat ~/.bashrc; echo "PS1=\"$(NEW_PS1) \"") || exit 0

$(VENV_DIR)/bin/activate:
	python3 -m venv venv

clean::
	rm -rf $(VENV_DIR)
