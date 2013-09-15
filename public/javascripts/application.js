// Place your application-specific JavaScript functions and classes here
// This file is automatically included by javascript_include_tag :defaults

if (window.Element && !('innerText' in Element.prototype) && 'textContent' in Element.prototype) {
  Element.prototype.__defineGetter__('innerText', function() {
    return this.textContent;
  });
  Element.prototype.__defineSetter__('innerText', function(text) {
    return this.textContent = text;
  });
}
