[![ci](https://github.com/clszzyh/elixir-composite-ci-action/workflows/ci/badge.svg)](https://github.com/clszzyh/elixir-composite-ci-action/actions)

## Useful links

* [Github action composite support new issue](https://github.com/actions/runner/issues/646)
* [Github action composite support old issue](https://github.com/actions/runner/issues/438)
* [Github action roadmap](https://github.com/github/roadmap/projects/1?card_filter_query=action)
* [Github action composite steps document](https://docs.github.com/en/free-pro-team@latest/actions/creating-actions/creating-a-composite-run-steps-action)
* [Github action syntax](https://docs.github.com/en/actions/reference/context-and-expression-syntax-for-github-actions)
* [Github api rest.js](https://octokit.github.io/rest.js/v18#checks-create)
* [Elixir release](https://github.com/elixir-lang/elixir/releases)
* [OTP releases](https://github.com/HashNuke/heroku-buildpack-elixir-otp-builds/blob/master/otp-versions)

```
- name: Get tag version
      id: get_tag_version
      run: echo ::set-output name=VERSION::${GITHUB_REF#refs/tags/}
    - name: Modify version
      if: contains(github.ref, 'tags/v')
      run: |
        NEW_VERSION=$(echo $VERSION | sed -e 's/^v//')
        echo $NEW_VERSION
        if [ -f VERSION ]; then echo $NEW_VERSION > VERSION; fi
      env:
        VERSION: ${{ steps.get_tag_version.outputs.VERSION }}
    - name: Set up Elixir
      uses: actions/setup-elixir@v1
      with:
        elixir-version: ${{ matrix.elixir }}
        otp-version: ${{ matrix.otp }}
    - name: Build info
      run: elixir -v
    - name: Print env
      run: env
    - name: Restore dependencies cache
      uses: actions/cache@v2
      id: mix-cache
      with:
        path: deps
        key: deps-${{ inputs.cache_version }}-${{ runner.os }}-${{ matrix.otp }}-${{ matrix.elixir }}-mix-${{ hashFiles(format('{0}{1}', github.workspace, '/mix.lock')) }}
        restore-keys: |
          deps-${{ inputs.cache_version }}-${{ runner.os }}-${{ matrix.otp }}-${{ matrix.elixir }}-mix
          deps-${{ inputs.cache_version }}-${{ runner.os }}-${{ matrix.otp }}
          deps-${{ inputs.cache_version }}-${{ runner.os }}
    - name: Restore build cache
      id: build-cache
      uses: actions/cache@v2
      with:
        path: _build
        key: build-${{ inputs.cache_version }}-${{ runner.os }}-${{ matrix.otp }}-${{ matrix.elixir }}-mix-${{ hashFiles(format('{0}{1}', github.workspace, '/mix.lock')) }}
        restore-keys: |
          build-${{ inputs.cache_version }}-${{ runner.os }}-${{ matrix.otp }}-${{ matrix.elixir }}-mix
          build-${{ inputs.cache_version }}-${{ runner.os }}-${{ matrix.otp }}
          build-${{ inputs.cache_version }}-${{ runner.os }}
    - name: Install dependencies
      run: mix deps.get
    - name: Compile
      run: mix compile --warnings-as-errors
      env:
        MIX_ENV: ${{ inputs.mix_env }}
    - name: Check Formatting
      run: mix format --check-formatted
    - name: Run Credo
      run: mix credo --strict
      env:
        MIX_ENV: ${{ inputs.mix_env }}
    - name: Run tests
      run: mix test
      env:
        MIX_ENV: ${{ inputs.mix_env }}
    - name: Retrieve PLT Cache
      uses: actions/cache@v2
      id: plt-cache
      with:
        path: priv/plts
        key: plts-${{ secrets.cache_version }}-${{ runner.os }}-${{ matrix.otp }}-${{ matrix.elixir }}-mix-${{ hashFiles(format('{0}{1}', github.workspace, '/mix.lock')) }}
        restore-keys: |
          plts-${{ secrets.cache_version }}-${{ runner.os }}-${{ matrix.otp }}-${{ matrix.elixir }}-mix
    - name: Create PLTs
      if: steps.plt-cache.outputs.cache-hit != 'true'
      run: mix dialyzer --plt
      env:
        MIX_ENV: ${{ inputs.mix_env }}
    - name: Run dialyzer
      run: mix dialyzer --no-check
      env:
        MIX_ENV: ${{ inputs.mix_env }}
    - name: Check Doc
      run: mix docs -f html && ! mix docs -f html 2>&1 | grep -q "warning:"
      env:
        MIX_ENV: prod
    - name: Deploy doc
      uses: peaceiris/actions-gh-pages@v3
      with:
        github_token: ${{ github.token }}
        publish_dir: ./doc
        force_orphan: true
        commit_message: ${{ github.event.head_commit.message || 'unknown' }}
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v1
    - name: Docker meta
      id: docker_meta
      uses: crazy-max/ghaction-docker-meta@v1
      with:
        images: ghcr.io/${{ github.repository }} # list of Docker images to use as base name for tags
        tag-sha: true # add git short SHA as Docker tag
        tag-semver: |
          {{version}}
          {{major}}.{{minor}}.{{patch}}
    - name: Cache Docker layers
      uses: actions/cache@v2
      with:
        path: /tmp/.buildx-cache
        key: docker-${{ inputs.cache_version }}-${{ runner.os }}-buildx-${{ github.sha }}
        restore-keys: |
          docker-${{ inputs.cache_version }}-${{ runner.os }}-buildx-
    - name: Login to GitHub Container Registry
      uses: docker/login-action@v1
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ inputs.pat }}
    - name: Build and push image
      uses: docker/build-push-action@v2
      id: docker_build
      with:
        context: .
        file: ./Dockerfile
        cache-from: type=local,src=/tmp/.buildx-cache
        cache-to: type=local,mode=max,dest=/tmp/.buildx-cache
        push: true
        build-args: |
          GIT_REV=${{ github.sha }}
        tags: ${{ steps.docker_meta.outputs.tags }}
        labels: ${{ steps.docker_meta.outputs.labels }}
    - name: Image digest
      run: echo ${{ steps.docker_build.outputs.digest }}
    - name: CI failed
      if: failure() && contains(github.ref, 'refs/heads')
      uses: clszzyh/github-script@main
      env:
        RUN_ID: ${{ steps.get_run_id.outputs.RUN_ID }}
        RUN_NUMBER: ${{ steps.get_run_id.outputs.RUN_NUMBER }}
        JOB: ${{ steps.get_run_id.outputs.JOB }}
      with:
        github-token: ${{github.token}}
        personal-token: ${{inputs.pat}}
        script: |
          commit_message = context.payload.commits[0].message.split("\n")[0]
          const check_runs = await github.checks.listForRef({
            owner: context.repo.owner,
            repo: context.repo.repo,
            ref: context.sha
          })

          const check_run_id = check_runs.data.check_runs[0].id

          title = `[CI FAIL] ${commit_message}`
          body = `
            <table><tbody><tr><td><details><summary>

            | Context | Value |
            | - | -: |
            | sha | ${context.sha} |
            | ref | ${context.ref} |
            | event | ${context.eventName} |
            | workflow | ${context.workflow} |
            | action | ${context.action} |
            | job | ${process.env.JOB} |
            | number | ${process.env.RUN_NUMBER} |
            | jid | [${process.env.RUN_ID}](${context.payload.repository.url}/actions/runs/${process.env.RUN_ID}) |
            | check_id | [${check_run_id}](${context.payload.repository.url}/runs/${check_run_id}?check_suite_focus=true) |
            | timestamp | ${context.payload.commits[0].timestamp} |
            | before | ${context.payload.before} |

            </summary><hr>

            ## Payload

            \`\`\`json
            ${JSON.stringify(context.payload, null, 2)}
            \`\`\`
            </details></td></tr></tbody>
            </table>
          `

          result = await github.issues.create({
            owner: context.repo.owner,
            repo: context.repo.repo,
            title: title,
            body: body,
            labels: ['ci']
          })

          github.reactions.createForIssue({
            owner: context.repo.owner,
            repo: context.repo.repo,
            issue_number: result.data.number,
            content: "eyes"
          })

          comment = await github.repos.createCommitComment({
            owner: context.repo.owner,
            repo: context.repo.repo,
            commit_sha: context.sha,
            body: "Related #" + result.data.number
          })

          const workflows_resp = await github.actions.listRepoWorkflows({
            owner: context.repo.owner,
            repo: context.repo.repo,
          })

          const workflows = workflows_resp.data.workflows
          workflow_id = null
          for (workflow of workflows) {
            if (workflow.name === "append_annotations") {
              workflow_id = workflow.id
            }
          }

          if (!workflow_id) {
            throw("Not found workflow")
          }

          console.log(process.env)

          dispatch_result = await personal_github.actions.createWorkflowDispatch({
            owner: context.repo.owner,
            repo: context.repo.repo,
            workflow_id: workflow_id,
            ref: context.ref,
            inputs: {"issue_number": result.data.number + ""}
          })
          console.log(dispatch_result)

    - name: Complete time
      id: cost
      if: always() && contains(github.ref, 'refs/heads')
      run: |
        END_TIME=$(date +%s)
        ELAPSE=$(( $END_TIME - $START_TIME ))
        echo "$(($ELAPSE/60))m$(($ELAPSE%60))s"
        COST="$(($ELAPSE/60))m$(($ELAPSE%60))s"
        echo ::set-output name=COST::$COST
      env:
        START_TIME: ${{ steps.get_run_id.outputs.START_TIME }}
    - name: CI Success
      if: success() && contains(github.ref, 'refs/heads')
      uses: actions/github-script@v3.1
      env:
        RUN_ID: ${{ steps.get_run_id.outputs.RUN_ID }}
        RUN_NUMBER: ${{ steps.get_run_id.outputs.RUN_NUMBER }}
        JOB: ${{ steps.get_run_id.outputs.JOB }}
      with:
        github-token: ${{github.token}}
        script: |
          const opts = github.issues.listForRepo.endpoint.merge({
            ...context.issue,
            state: 'open',
            labels: 'ci'
          })
          const issues = await github.paginate(opts)
          commit_message = context.payload.commits[0].message.split("\n")[0]

          issue_body = `
          ## Closing this.

          | Context | Value |
          | - | -: |
          | sha | ${context.sha} |
          | ref | ${context.ref} |
          | event | ${context.eventName} |
          | workflow | ${context.workflow} |
          | action | ${context.action} |
          | job | ${process.env.JOB} |
          | number | ${process.env.RUN_NUMBER} |
          | jid | [${process.env.RUN_ID}](${context.payload.repository.url}/actions/runs/${process.env.RUN_ID}) |
          | timestamp | ${context.payload.commits[0].timestamp} |
          | before | ${context.payload.before} |
          `

          commit_body = []
          for (const issue of issues) {
            commit_body.push("#" + issue.number)
          }
          if(commit_body.length > 0) {
            github.repos.createCommitComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              commit_sha: context.sha,
              body: "Close " + commit_body.join(", ")
            })
          }

          for (const issue of issues) {
            comment = await github.issues.createComment({
              issue_number: issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: issue_body
            })
            github.reactions.createForIssueComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              comment_id: comment.data.id,
              content: "hooray"
            })
            github.issues.update({
              issue_number: issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              state: 'closed',
              title: issue.title + ` [Fixed by ${commit_message}]`
            })
          }
```
