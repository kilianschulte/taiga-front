
module = angular.module('taigaBacklog')

BelongToSprintDirective = () ->

    return {
        scope: {
            sprint: '='
        },
        templateUrl: "components/belong-to-sprint/belong-to-sprint-text.html"
    }


module.directive("tgBelongToSprint", BelongToSprintDirective)
