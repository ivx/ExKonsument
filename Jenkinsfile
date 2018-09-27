def app_name = 'ExKonsument'

stage('Checkout') {
  node {
    checkout scm
  }
}

timeout(time: 20, unit: 'MINUTES') {
  stage('Test') {
    node {
      try {
        sh "docker-compose build --pull"
        sh "docker-compose run app test"
      } finally {
        sh 'docker-compose down -v --remove-orphans'
      }
    }
  }
}
