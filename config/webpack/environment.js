const { environment } = require('@rails/webpacker')
const webpack = require('webpack')

environment.plugins.prepend('Provide',
  new webpack.ProvidePlugin({
    $: 'jquery',
    jQuery: 'jquery',
    jquery: 'jquery'
  })
)

environment.plugins.append('Provide',
  new webpack.ProvidePlugin({
    Popper: ['@popperjs/core', 'default']
  })
)

environment.config.merge({
  resolve: {
    fallback: {
      dgram: false,
      fs: false,
      net: false,
      tls: false,
      child_process: false
    }
  },
  node: false
})

module.exports = environment
