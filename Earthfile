VERSION 0.8

# WORKTODO(adam): do packaging. Rahul says this can be a github mirror instead of the current published npm package
publish-npm:
    FROM ../+bootstrap
    ARG VERSION
    ARG DIST_TAG
    ARG DRY_RUN=0
    WORKDIR /usr/src/l1-contracts
    RUN --secret NPM_TOKEN echo "//registry.npmjs.org/:_authToken=${NPM_TOKEN}" > .npmrc
    RUN jq --arg v $VERSION '.version = $v' package.json > _tmp.json && mv  _tmp.json package.json
    RUN if [ "$DRY_RUN" = "1" ]; then \
        npm publish --tag $DIST_TAG --access public --dry-run; \
    else \
        npm publish --tag $DIST_TAG --access public; \
    fi
