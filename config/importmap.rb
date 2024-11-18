# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin "jquery", to: "https://ga.jspm.io/npm:jquery@3.7.1/dist/jquery.js"
pin "bootstrap", to: "https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.esm.min.js"

# Pin all controllers
pin "controllers/application", to: "controllers/application.js", preload: true
pin "controllers/index", to: "controllers/index.js", preload: true
pin "controllers/form_controller", to: "controllers/form_controller.js"
pin "controllers/sort_controller", to: "controllers/sort_controller.js"
pin "controllers/view_toggle_controller", to: "controllers/view_toggle_controller.js"

# Pin stimulus-loading
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "chartkick", to: "chartkick.js"
pin "Chart.bundle", to: "Chart.bundle.js"