module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
  ],
  rules: {
    "quotes": "off",
    "indent": "off", 
    "max-len": "off",
    "no-trailing-spaces": "off",
    "arrow-parens": "off",
    "eol-last": "off",
    "no-unused-vars": "off",
  },
  parserOptions: {
    ecmaVersion: 2020,
  },
};
