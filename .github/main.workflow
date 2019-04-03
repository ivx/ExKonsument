workflow "Build, test and publish" {
  on = "push"
  resolves = [
    "Test code"
  ]
}

action "Build docker image" {
  uses = "actions/docker/cli@master"
  args = "build -t app ."
}

action "Test code" {
  needs = ["Build docker image"]
  uses = "actions/docker/cli@master"
  args = ["run app test"]
}
