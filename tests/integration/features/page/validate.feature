Feature: page/validate

  Scenario: Unauthenticated user can see sign page
    Given as user "admin"
    And sending "delete" to ocs "/apps/provisioning_api/api/v1/config/apps/libresign/make_validation_url_private"
    And as user ""
    When sending "get" to "/apps/libresign/p/validation"
    And the response should contain the initial state "libresign-config" with the following values:
      """
      []
      """

  Scenario: Unauthenticated user can not see sign page
    Given as user "admin"
    Given sending "post" to ocs "/apps/provisioning_api/api/v1/config/apps/libresign/make_validation_url_private"
      | value | 1 |
    And as user ""
    When sending "get" to "/apps/libresign/p/validation"
    And the response should be a JSON array with the following mandatory values
      | key     | value                         |
      | message | Current user is not logged in |