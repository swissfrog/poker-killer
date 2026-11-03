[app]

title = Poker Helper
package.name = pokerhelper
package.domain = de.swissfrog
source.dir = .
source.include_exts = py,kv,json
source.exclude_dirs = .git,tests,trainer,test_checkout
version = 0.1.0

requirements = python3,kivy
orientation = portrait
fullscreen = 0

android.permissions = CAMERA
android.minapi = 23
android.api = 35
android.archs = arm64-v8a
p4a.bootstrap = sdl2

[buildozer]

log_level = 2
warn_on_root = 1
