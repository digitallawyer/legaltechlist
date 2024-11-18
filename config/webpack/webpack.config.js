const path = require('path')

module.exports = {
  mode: "production",
  entry: {
    application: path.resolve(__dirname, '../../app/javascript/packs/application.js')
  },
  output: {
    filename: "[name].js",
    path: path.resolve(__dirname, "../../app/assets/builds")
  },
  resolve: {
    extensions: ['.js', '.jsx']
  },
  module: {
    rules: [
      {
        test: /\.(js|jsx)$/,
        exclude: /node_modules/,
        use: ['babel-loader'],
      }
    ]
  }
}
