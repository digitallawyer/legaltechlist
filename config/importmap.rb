# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
pin "jquery", to: "https://ga.jspm.io/npm:jquery@3.7.1/dist/jquery.js"

# Pin all controllers
pin "controllers/application", to: "controllers/application.js", preload: true
pin "controllers/index", to: "controllers/index.js", preload: true
pin "controllers/form_controller", to: "controllers/form_controller.js"
pin "controllers/sort_controller", to: "controllers/sort_controller.js"
pin "controllers/view_toggle_controller", to: "controllers/view_toggle_controller.js"

# Charting
pin "chartkick", to: "https://ga.jspm.io/npm:chartkick@5.0.1/dist/chartkick.esm.js"
pin "chart.js", to: "https://ga.jspm.io/npm:chart.js@4.4.1/dist/chart.umd.js"
