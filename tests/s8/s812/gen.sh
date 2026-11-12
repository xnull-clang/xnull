#!/bin/sh
set -eu
BASE=$(cd "$(dirname "$0")" && pwd)
mk() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
JAR() { mkdir -p "$(dirname "$1")"; printf 'jar:%s\n' "$2" > "$1"; }

# ---------- F1 ----------
R=$BASE/f1-parent
mk "$R/parent/xnull.project" <<'EOF'
project {
  groupId = s812
  artifactId = parent
  version = 1.0.0
  packaging = pom
  properties {
    xdk-version = 1.2.3
    language-version = 3.3.0
    sourceEntry = alt/src/main.x
  }
  build {
    sourceRoot = alt/src
    warnings = strict
  }
}
EOF
mk "$R/app/xnull.project" <<'EOF'
project {
  groupId = s812
  artifactId = app
  version = 1.0.0
  packaging = app
  parent {
    groupId = s812
    artifactId = parent
    version = 1.0.0
    relativePath = ../parent/xnull.project
  }
  properties {
    language-version = 3.4.0
  }
  profiles {
    profile dev {
      properties {
        language-version = 9.9.9
      }
    }
  }
}
EOF
mk "$R/app/alt/src/main.x" <<'EOF'
static Int main() {
    print("F1-MAIN-OK")
    return 0
}
EOF
mk "$R/app/src/test/x/main.x" <<'EOF'
static Int main() {
    print("F1-TEST-OK")
    return 0
}
EOF

# ---------- F2 ----------
R=$BASE/f2-dep-lock
libmeta() { mk "$R/repo/g/$1/$2/xnull.project" <<EOF
project {
  groupId = g
  artifactId = $1
  version = $2
  packaging = library
}
EOF
JAR "$R/repo/g/$1/$2/$1-$2.jar" "g:$1@$2"
}
depmeta() { # coord ver depcoord depver
  mk "$R/repo/g/$1/$2/xnull.project" <<EOF
project {
  groupId = g
  artifactId = $1
  version = $2
  packaging = library
  dependencies {
    dependency $3 {
      version = $4
    }
  }
}
EOF
JAR "$R/repo/g/$1/$2/$1-$2.jar" "g:$1@$2"
}
libmeta lib 1.0.0
libmeta lib 2.0.0
libmeta x 2.0.0
libmeta x 3.0.0
libmeta extra 1.0.0
depmeta top 1.0.0 g:lib 2.0.0
depmeta top 2.0.0 g:lib 2.0.0
depmeta a 1.0.0 g:x 2.0.0
depmeta b 1.0.0 g:x 3.0.0
depmeta c 1.0.0 g:d 1.0.0
depmeta d 1.0.0 g:c 1.0.0

appmeta() { # dir deps...
  d=$1; shift
  mkdir -p "$R/$d"
  {
    echo 'project {'
    echo '  groupId = s812'
    echo '  artifactId = app'
    echo '  version = 1.0.0'
    echo '  packaging = app'
    if [ "$#" -gt 0 ]; then
      echo '  dependencies {'
      for dep in "$@"; do
        echo "    dependency $dep {"
        echo '      version = 1.0.0'
        echo '    }'
      done
      echo '  }'
    fi
    echo '}'
  } > "$R/$d/xnull.project"
  mk "$R/$d/src/main/x/main.x" <<'EOF'
static Int main() {
    print("F2-MAIN-OK")
    return 0
}
EOF
}
appmeta app g:top
appmeta app-conflict g:a g:b
appmeta app-cycle g:c

# app-managed：管理表钉 g:lib 1.0.0
mk "$R/app-managed/xnull.project" <<'EOF'
project {
  groupId = s812
  artifactId = app
  version = 1.0.0
  packaging = app
  dependencies {
    dependency g:top {
      version = 1.0.0
    }
  }
  dependencyManagement {
    dependencies {
      dependency g:lib {
        version = 1.0.0
      }
    }
  }
}
EOF
mk "$R/app-managed/src/main/x/main.x" <<'EOF'
static Int main() {
    print("F2-MAIN-OK")
    return 0
}
EOF

# ---------- F3 ----------
R=$BASE/f3-integration
mk "$R/app/xnull.project" <<'EOF'
project {
  groupId = s812
  artifactId = app
  version = 1.0.0
  packaging = app
  properties {
    xdk-version = 1.0.0
    language-version = 3.3.0
    appName = demo
  }
  profiles {
    profile dev {
      properties {
        appName = demo-dev
      }
      configuration {
        app.env = dev-manifest
      }
    }
  }
  configuration {
    app.name = ${appName}
    app.env = base
    net.port = 8080
    feature.flag = true
  }
  build {
    resources {
      resource src/main/resources {
        includes = [**]
        excludes = [**/*.psd]
      }
      resource extra/resources {
        includes = [conf/**]
      }
    }
    plugins {
      plugin com.example:codegen 1.2.0 {
        phase = validate
        goal = check
        configuration {
          output = target/gen
        }
      }
    }
  }
}
EOF
mk "$R/app/src/main/x/main.x" <<'EOF'
static Int main() {
    print("F3-MAIN-OK")
    return 0
}
EOF
mk "$R/app/src/test/x/main.x" <<'EOF'
static Int main() {
    print("F3-TEST-OK")
    return 0
}
EOF
mk "$R/app/src/main/resources/application.properties" <<'EOF'
app.name = from-file
app.env = file
EOF
# application-dev.properties 由 F3-b 变体在执行时临时创建，基准夹具不写入
mkdir -p "$R/app/src/main/resources/templates"
printf 'hello\n' > "$R/app/src/main/resources/templates/a.txt"
printf 'skip\n'  > "$R/app/src/main/resources/skip.psd"
mkdir -p "$R/app/extra/resources/conf"
printf 'conf\n'  > "$R/app/extra/resources/conf/app.conf"
mk "$R/repo/com/example/codegen/1.2.0/.xplugin" <<'EOF'
plugin {
  groupId          = com.example
  artifactId       = codegen
  version          = 1.2.0
  toolchainVersion = 0.1.0
  goals {
    goal check {
      phase      = validate
      configKeys = [output]
    }
  }
}
EOF
JAR "$R/repo/com/example/codegen/1.2.0/codegen-1.2.0.jar" "com.example:codegen@1.2.0"

echo "fixtures written to $BASE"
