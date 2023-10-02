Feature: page/sign_identify_default

  Scenario: Open sign file with all data valid
    Given as user "admin"
    And sending "delete" to ocs "/apps/provisioning_api/api/v1/config/apps/libresign/identify_methods"
    When sending "get" to "/apps/libresign/f/"
    Then the response should have a status code 200
    And the response should contain the initial state "libresign-identify_methods" with the following values:
      """
      [
        {"name":"account","friendly_name":"Account","enabled":true,"mandatory":true,"can_create_account":true,"signature_method":"password","allowed_signature_methods":["password"]},
        {"name":"email","friendly_name":"Email","enabled":false,"mandatory":true,"test_url":"/index.php/settings/admin/mailtest"}
      ]
      """