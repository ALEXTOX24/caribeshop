.PHONY: fmt validate check-python safety

fmt:
	terraform fmt -recursive

validate:
	cd bootstrap && terraform init -backend=false && terraform validate
	cd infra && terraform init -backend=false && terraform validate

check-python:
	python3 -m py_compile app/app.py loadtest/locustfile.py

safety:
	./scripts/repo-safety-check.sh
