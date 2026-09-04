import QtQuick
import QtTest
import "../.."

TestCase {
  name: "CatalogImage"
  when: windowShown

  CatalogImage {
    id: image
    width: 32
    height: 32
    maxRetryAttempts: 1
  }

  function init() {
    image.requestedSource = ""
    compare(image.retryAttempt, 0)
    compare(image.retryNonce, 0)
  }

  function test_failed_image_retries_once_and_resets_for_new_source() {
    image.requestedSource = "file:///definitely-missing-omarchy-catalog-image.png"
    tryCompare(image, "retryAttempt", 1, 1000)
    verify(image.retrying)
    tryCompare(image, "retryNonce", 1, 1500)
    tryCompare(image, "status", Image.Error, 1000)
    verify(!image.retrying)

    image.requestedSource = ""
    compare(image.retryAttempt, 0)
    compare(image.retryNonce, 0)
  }
}
