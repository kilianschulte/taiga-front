###
# Copyright (C) 2014-2017 Andrey Antukh <niwi@niwi.nz>
# Copyright (C) 2014-2017 Jesús Espino Garcia <jespinog@gmail.com>
# Copyright (C) 2014-2017 David Barragán Merino <bameda@dbarragan.com>
# Copyright (C) 2014-2017 Alejandro Alonso <alejandro.alonso@kaleidos.net>
# Copyright (C) 2014-2017 Juan Francisco Alcántara <juanfran.alcantara@kaleidos.net>
# Copyright (C) 2014-2017 Xavi Julian <xavier.julian@kaleidos.net>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# File: modules/controllerMixins.coffee
###

taiga = @.taiga

groupBy = @.taiga.groupBy
joinStr = @.taiga.joinStr
trim = @.taiga.trim
toString = @.taiga.toString


#############################################################################
## Page Mixin
#############################################################################

class PageMixin
    fillUsersAndRoles: (users, roles) ->
        activeUsers = _.filter(users, (user) => user.is_active)
        @scope.activeUsers = _.sortBy(activeUsers, "full_name_display")
        @scope.activeUsersById = groupBy(@scope.activeUsers, (e) -> e.id)

        @scope.users = _.sortBy(users, "full_name_display")
        @scope.usersById = groupBy(@scope.users, (e) -> e.id)

        @scope.roles = _.sortBy(roles, "order")
        computableRoles = _(@scope.project.members).map("role").uniq().value()
        @scope.computableRoles = _(roles).filter("computable")
                                         .filter((x) -> _.includes(computableRoles, x.id))
                                         .value()
    loadUsersAndRoles: ->
        promise = @q.all([
            @rs.projects.usersList(@scope.projectId),
            @rs.projects.rolesList(@scope.projectId)
        ])

        return promise.then (results) =>
            [users, roles] = results
            @.fillUsersAndRoles(users, roles)
            return results

taiga.PageMixin = PageMixin


#############################################################################
## Filters Mixin
#############################################################################
# This mixin requires @location ($tgLocation), and @scope

class FiltersMixin
    selectFilter: (name, value, load=false) ->
        params = @location.search()
        if params[name] != undefined and name != "page"
            existing = _.map(taiga.toString(params[name]).split(","), (x) -> trim(x))
            existing.push(taiga.toString(value))
            existing = _.compact(existing)
            value = joinStr(",", _.uniq(existing))

        if !@location.isInCurrentRouteParams(name, value)
            location = if load then @location else @location.noreload(@scope)
            location.search(name, value)

    replaceFilter: (name, value, load=false) ->
        if !@location.isInCurrentRouteParams(name, value)
            location = if load then @location else @location.noreload(@scope)
            location.search(name, value)

    replaceAllFilters: (filters, load=false) ->
        location = if load then @location else @location.noreload(@scope)
        location.search(filters)

    unselectFilter: (name, value, load=false) ->
        params = @location.search()

        if params[name] is undefined
            return

        if value is undefined or value is null
            delete params[name]

        parsedValues = _.map(taiga.toString(params[name]).split(","), (x) -> trim(x))
        newValues = _.reject(parsedValues, (x) -> x == taiga.toString(value))
        newValues = _.compact(newValues)

        if _.isEmpty(newValues)
            value = null
        else
            value = joinStr(",", _.uniq(newValues))

        location = if load then @location else @location.noreload(@scope)
        location.search(name, value)

    applyStoredFilters: (projectSlug, key) ->
        if _.isEmpty(@location.search())
            filters = @.getFilters(projectSlug, key)
            if Object.keys(filters).length
                @location.search(filters)
                @location.replace()

                return true

        return false

    storeFilters: (projectSlug, params, filtersHashSuffix) ->
        ns = "#{projectSlug}:#{filtersHashSuffix}"
        hash = taiga.generateHash([projectSlug, ns])
        @storage.set(hash, params)

    getFilters: (projectSlug, filtersHashSuffix) ->
        ns = "#{projectSlug}:#{filtersHashSuffix}"
        hash = taiga.generateHash([projectSlug, ns])

        return @storage.get(hash) or {}

    formatSelectedFilters: (type, list, urlIds) ->
        selectedIds = urlIds.split(',')
        selectedFilters = _.filter list, (it) ->
            selectedIds.indexOf(_.toString(it.id)) != -1

        invalidTags = _.filter selectedIds, (it) ->
            return !_.find selectedFilters, (sit) -> _.toString(sit.id) == it

        invalidAppliedTags =  _.map invalidTags, (it) ->
            return {
                id: it
                key: type + ":" + it
                dataType: type,
                name: it
            }

        validAppliedTags = _.map selectedFilters, (it) ->
            return {
                id: it.id
                key: type + ":" + it.id
                dataType: type,
                name: it.name
                color: it.color
            }

        return invalidAppliedTags.concat(validAppliedTags)

taiga.FiltersMixin = FiltersMixin

#############################################################################
## Us Filters Mixin
#############################################################################

class UsFiltersMixin
    changeQ: (q) ->
        @.replaceFilter("q", q)
        @.filtersReloadContent()
        @.generateFilters()

    removeFilter: (filter) ->
        @.unselectFilter(filter.dataType, filter.id)
        @.filtersReloadContent()
        @.generateFilters()

    addFilter: (newFilter) ->
        @.selectFilter(newFilter.category.dataType, newFilter.filter.id)
        @.filtersReloadContent()
        @.generateFilters()

    selectCustomFilter: (customFilter) ->
        @.replaceAllFilters(customFilter.filter)
        @.filtersReloadContent()
        @.generateFilters()

    saveCustomFilter: (name) ->
        filters = {}
        urlfilters = @location.search()
        filters.tags = urlfilters.tags
        filters.status = urlfilters.status
        filters.assigned_to = urlfilters.assigned_to
        filters.owner = urlfilters.owner
        filters.epic = urlfilters.epic

        @filterRemoteStorageService.getFilters(@scope.projectId, @.storeCustomFiltersName).then (userFilters) =>
            userFilters[name] = filters

            @filterRemoteStorageService.storeFilters(@scope.projectId, userFilters, @.storeCustomFiltersName).then(@.generateFilters)

    removeCustomFilter: (customFilter) ->
        @filterRemoteStorageService.getFilters(@scope.projectId, @.storeCustomFiltersName).then (userFilters) =>
            delete userFilters[customFilter.id]

            @filterRemoteStorageService.storeFilters(@scope.projectId, userFilters, @.storeCustomFiltersName).then(@.generateFilters)
            @.generateFilters()

    filtersData: (params) ->
        return @q.all([
          @rs.userstories.filtersData(params),
          @rs.sprints.list(@scope.projectId),
          @rs.userstories.listUnassigned(@scope.projectId),
          @rs.tasks.filtersData({project: @scope.projectId})
        ]).then (data) =>

            sprints = data[1].milestones.filter((m) -> !m.closed).map (m) ->
                return {id: m.id, name: m.name, count: m.user_stories.length}
            sprints.unshift({id: null, count: data[2][0].length})
            data[0].sprints = sprints

            task_involved = data[3].assigned_to

            involved = data[0].assigned_to.map (e) =>
                task = task_involved.find (t) => t.id == e.id
                if task
                    task_involved.splice(task_involved.indexOf(task), 1)
                    return _.extend({}, e, {count: e.count + task.count})
                else
                    return _.extend({}, e)
            involved.concat(task_involved)
            data[0].involved = involved;

            return data[0]

    generateFilters: ->
        @.storeFilters(@params.pslug, @location.search(), @.storeFiltersName)

        urlfilters = @location.search()

        loadFilters = {}
        loadFilters.project = @scope.projectId
        loadFilters.tags = urlfilters.tags
        loadFilters.status = urlfilters.status
        loadFilters.assigned_to = urlfilters.assigned_to
        loadFilters.owner = urlfilters.owner
        loadFilters.epic = urlfilters.epic
        loadFilters.q = urlfilters.q

        extendedFilters = {
          milestone: urlfilters.milestone,
          involved: urlfilters.involved
        }

        return @q.all([
            @.filtersData(loadFilters),
            @filterRemoteStorageService.getFilters(@scope.projectId, @.storeCustomFiltersName)
        ]).then (result) =>
            data = result[0]
            customFiltersRaw = result[1]

            statuses = _.map data.statuses, (it) ->
                it.id = it.id.toString()

                return it
            tags = _.map data.tags, (it) ->
                it.id = it.name

                return it
            tagsWithAtLeastOneElement = _.filter tags, (tag) ->
                return tag.count > 0
            assignedTo = _.map data.assigned_to, (it) ->
                if it.id
                    it.id = it.id.toString()
                else
                    it.id = "null"

                it.name = it.full_name || "Unassigned"

                return it
            owner = _.map data.owners, (it) ->
                it.id = it.id.toString()
                it.name = it.full_name

                return it
            epic = _.map data.epics, (it) ->
                if it.id
                    it.id = it.id.toString()
                    it.name = "##{it.ref} #{it.subject}"
                else
                    it.id = "null"
                    it.name = "Not in an epic"

                return it
            sprint = _.map data.sprints, (it) ->
                if it.id
                    it.id = it.id.toString()
                    it.name = "Sprint #{it.name}"
                else
                    it.id = "null"
                    it.name = "Not in a sprint"

                return it

            involved = _.map data.involved, (it) ->
                if (it.id)
                    it.id = it.id.toString()
                else
                    it.id = "null"

                it.name = it.full_name || "Unassigned"

                return it

            @.selectedFilters = []

            if loadFilters.status
                selected = @.formatSelectedFilters("status", statuses, loadFilters.status)
                @.selectedFilters = @.selectedFilters.concat(selected)

            if loadFilters.tags
                selected = @.formatSelectedFilters("tags", tags, loadFilters.tags)
                @.selectedFilters = @.selectedFilters.concat(selected)

            if loadFilters.assigned_to
                selected = @.formatSelectedFilters("assigned_to", assignedTo, loadFilters.assigned_to)
                @.selectedFilters = @.selectedFilters.concat(selected)

            if loadFilters.owner
                selected = @.formatSelectedFilters("owner", owner, loadFilters.owner)
                @.selectedFilters = @.selectedFilters.concat(selected)

            if loadFilters.epic
                selected = @.formatSelectedFilters("epic", epic, loadFilters.epic)
                @.selectedFilters = @.selectedFilters.concat(selected)

            if extendedFilters.milestone
                selected = @.formatSelectedFilters("milestone", sprint, extendedFilters.milestone)
                @.selectedFilters = @.selectedFilters.concat(selected)

            if (extendedFilters.involved)
                selected = @.formatSelectedFilters("involved", involved, extendedFilters.involved)
                @.selectedFilters = @.selectedFilters.concat(selected)

            @.filterQ = loadFilters.q

            @.filters = [
                {
                    title: @translate.instant("COMMON.FILTERS.CATEGORIES.STATUS"),
                    dataType: "status",
                    content: statuses
                },
                {
                    title: @translate.instant("COMMON.FILTERS.CATEGORIES.TAGS"),
                    dataType: "tags",
                    content: tags,
                    hideEmpty: true,
                    totalTaggedElements: tagsWithAtLeastOneElement.length
                },
                {
                    title: @translate.instant("COMMON.FILTERS.CATEGORIES.ASSIGNED_TO"),
                    dataType: "assigned_to",
                    content: assignedTo
                },
                {
                    title: @translate.instant("COMMON.FILTERS.CATEGORIES.CREATED_BY"),
                    dataType: "owner",
                    content: owner
                },
                {
                    title: @translate.instant("COMMON.FILTERS.CATEGORIES.EPIC"),
                    dataType: "epic",
                    content: epic
                },
                {
                    title: @translate.instant("COMMON.FILTERS.CATEGORIES.SPRINT"),
                    dataType: "milestone",
                    content: sprint
                },
                {
                    title: @translate.instant("COMMON.FILTERS.CATEGORIES.INVOLVED"),
                    dataType: "involved",
                    content: involved
                }
            ]

            @.customFilters = []
            _.forOwn customFiltersRaw, (value, key) =>
                @.customFilters.push({id: key, name: key, filter: value})


taiga.UsFiltersMixin = UsFiltersMixin
