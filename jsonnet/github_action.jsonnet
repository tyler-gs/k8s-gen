local onMaster = { 'if': "${{ github.ref == 'refs/heads/master' && github.repository == 'jsonnet-libs/k8s' }}" };
local onPR = { 'if': "${{ github.ref != 'refs/heads/master' && github.repository == 'jsonnet-libs/k8s' }}" };
local terraform = {
  job: {
    make_env:: {
      env: {
        PAGES: 'false',
      },
    },
    tf_env:: {
      'working-directory': 'tf',
      env: {
        GITHUB_TOKEN: '${{ secrets.PAT }}',
        TF_IN_AUTOMATION: '1',
      },
    },
    name: 'Create repositories',
    'runs-on': 'ubuntu-latest',
    steps: [
      { uses: 'actions/checkout@v2' },
      { uses: 'zendesk/setup-jsonnet@v7' },

      self.make_env { run: 'make tf/main.tf.json' },

      {
        uses: 'hashicorp/setup-terraform@v1',
        with: {
          cli_config_credentials_token: '${{ secrets.TF_API_TOKEN }}',
        },
      },
      self.tf_env { run: 'terraform init' },
      self.tf_env { run: 'terraform validate -no-color' },
      self.tf_env + onPR { run: 'terraform plan -no-color' },
      self.tf_env + onMaster { run: 'terraform apply -no-color -auto-approve' },
    ],
  },
  withPages(needs): {
    name: 'Set up gh-pages branch',
    needs: needs,
    make_env+:: {
      env+: {
        PAGES: 'true',
      },
    },
  },
};


function(libs) {
  '.github/workflows/main.yml':
    '# Generated by `make configure`, please do not edit manually.\n' + std.manifestYamlDoc({
      on: [
        'push',
      ],
      jobs: {
        [lib.name]: {
          name: 'Generate ' + lib.name + ' Jsonnet library and docs',
          needs: 'repos',
          'runs-on': 'ubuntu-latest',
          steps: [
            { uses: 'actions/checkout@v2' },
            onMaster {
              run: |||
                mkdir ~/.ssh
                echo "${{ secrets.DEPLOY_KEY }}" > ~/.ssh/id_rsa
                chmod 600 ~/.ssh/id_rsa
                export GEN_COMMIT=1
              |||,
            },
            { run: 'make build libs/' + lib.name },
          ],
        }
        for lib in libs
      } + {
        debugging: {
          name: 'Debugging Github Action values',
          'runs-on': 'ubuntu-latest',
          steps: [
            { run: 'echo isMaster? ' + onMaster['if'] },
            { run: 'echo isPR? ' + onPR['if'] },
            { run: 'echo ${{ github.repository }}' },
            { run: 'echo ${{ github.ref }}' },
            { run: 'echo ${{ github.event_name }}' },
          ],
        },
        repos: terraform.job,
        repos_with_pages: terraform.job + terraform.withPages([lib.name for lib in libs]),
      },
    }),
}