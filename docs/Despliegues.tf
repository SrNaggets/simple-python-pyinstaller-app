terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {}

resource "docker_network" "jenkins_network" {
  name = "jenkins-network"
}

resource "docker_volume" "jenkins_volume" {
  name = "jenkins-volume"
}

resource "docker_image" "dind_image" {
  name         = "docker:20.10.24-dind"
  keep_locally = false
}

resource "docker_container" "dind_container" {
  image       = docker_image.dind_image.name
  name        = "dind"
  privileged  = true

  networks_advanced {
    name    = docker_network.jenkins_network.name
    aliases = ["dind"]
  }

  ports {
    internal = 2375
    external = 2375
  }

  command = [
    "dockerd",
    "--host=tcp://0.0.0.0:2375",
    "--host=unix:///var/run/docker.sock"
  ]
}

resource "docker_container" "jenkins_container" {
  image       = "myjenkins-blueocean"  
  name        = "jenkins"
  restart = "unless-stopped"
  depends_on = [docker_container.dind_container]

  networks_advanced {
    name = docker_network.jenkins_network.name
  }
  env = [
    "DOCKER_HOST=tcp://dind:2375"
  ]

  volumes {
    volume_name   = docker_volume.jenkins_volume.name
    container_path = "/var/jenkins_home"
  }

  ports {
    internal = 8080
    external = 8080
  }

  ports {
    internal = 50000
    external = 50000
  }
}

