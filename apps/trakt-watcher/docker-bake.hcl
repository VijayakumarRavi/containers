target "docker-metadata-action" {}

variable "APP" {
  default = "trakt-watcher"
}

variable "VERSION" {
  // renovate: datasource=pypi depName=trakt.py
  default = "4.4.0"
}

variable "SOURCE" {
  default = "https://github.com/benscobie/radarr_sonarr_watchmon"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION = "${VERSION}"
  }
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output = ["type=docker"]
  tags = ["${APP}:${VERSION}"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64",
    "linux/arm64"
  ]
}
