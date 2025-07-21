# Copyright 2021,2025 Hewlett Packard Enterprise Development LP

CHART_METADATA_IMAGE ?= artifactory.algol60.net/csm-docker/stable/chart-metadata
YQ_IMAGE ?= artifactory.algol60.net/docker.io/mikefarah/yq:4
HELM_IMAGE ?= artifactory.algol60.net/docker.io/alpine/helm:3.7.1
HELM_UNITTEST_IMAGE ?= artifactory.algol60.net/docker.io/quintush/helm-unittest
HELM_DOCS_IMAGE ?= artifactory.algol60.net/docker.io/jnorwood/helm-docs:v1.5.0

all: dep-up lint test package

helm:
	docker run --rm \
		--user $(shell id -u):$(shell id -g) \
		--mount type=bind,src="$(shell pwd)",dst=/src \
		-w /src \
		-e HELM_CACHE_HOME=/src/.helm/cache \
		-e HELM_CONFIG_HOME=/src/.helm/config \
		-e HELM_DATA_HOME=/src/.helm/data \
		$(HELM_IMAGE) \
		$(CMD)

dep-up:
	CMD="dep up charts/sealed-secrets" $(MAKE) helm
	$(MAKE) copy-crds

copy-crds:
	@echo "Copying CRDs from dependency chart to files directory..."
	@mkdir -p charts/sealed-secrets/files
	@cd charts/sealed-secrets/charts && \
	if [ -f sealed-secrets-*.tgz ]; then \
		echo "Extracting dependency chart CRDs..."; \
		if tar -xzf sealed-secrets-*.tgz -C ../files --strip-components 2 sealed-secrets/crds/bitnami.com_sealedsecrets.yaml; then \
			echo "CRDs copied successfully"; \
		else \
			echo "Warning: Failed to extract CRDs from dependency chart"; \
		fi; \
	else \
		echo "Warning: Dependency chart sealed-secrets-*.tgz file not found"; \
	fi

lint:
	CMD="lint charts/sealed-secrets" $(MAKE) helm

test:
	docker run --rm \
		-v ${PWD}/charts:/apps \
		${HELM_UNITTEST_IMAGE} \
		sealed-secrets

package:
ifdef CHART_VERSIONS
	CMD="package charts/sealed-secrets --version $(word 1, $(CHART_VERSIONS)) -d packages" $(MAKE) helm
else
	CMD="package charts/* -d packages" $(MAKE) helm
endif

extracted-images:
	CMD="template release $(CHART) --dry-run --replace --dependency-update" $(MAKE) -s helm \
	| docker run --rm -i $(YQ_IMAGE) e -N '.. | .image? | select(.)' -

annotated-images:
	CMD="show chart $(CHART)" $(MAKE) -s helm \
	| docker run --rm -i $(YQ_IMAGE) e -N '.annotations."artifacthub.io/images"' - \
	| docker run --rm -i $(YQ_IMAGE) e -N '.. | .image? | select(.)' -

images:
	CHART=charts/sealed-secrets $(MAKE) -s extracted-images annotated-images | sort -u

snyk:
	$(MAKE) -s images | xargs --verbose -n 1 snyk container test

gen-docs:
	docker run --rm \
		--user $(shell id -u):$(shell id -g) \
		--mount type=bind,src="$(shell pwd)",dst=/src \
		-w /src \
		$(HELM_DOCS_IMAGE) \
		helm-docs --chart-search-root=charts

clean:
	$(RM) -r .helm packages charts/sealed-secrets/charts
