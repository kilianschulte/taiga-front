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
# File: modules/resources/userstories.coffee
###

taiga = @.taiga

generateHash = taiga.generateHash

resourceProvider = ($repo, $http, $urls, $storage, $q) ->
    service = {}
    hashSuffix = "userstories-queryparams"

    service.get = (projectId, usId, extraParams) ->
        params = service.getQueryParams(projectId)
        params.project = projectId

        params = _.extend({}, params, extraParams)

        return $repo.queryOne("userstories", usId, params)

    service.getByRef = (projectId, ref, extraParams = {}) ->
        params = service.getQueryParams(projectId)
        params.project = projectId
        params.ref = ref
        params = _.extend({}, params, extraParams)

        return $repo.queryOne("userstories", "by_ref", params)

    service.listInAllProjects = (filters) ->
        return $repo.queryMany("userstories", filters)

    service.filtersData = (params) ->
        return $repo.queryOneRaw("userstories-filters", null, params)

    service.listUnassigned = (projectId, filters, pageSize) ->
        params = {"project": projectId, "milestone": "null"}
        params = _.extend({}, params, filters or {})
        service.storeQueryParams(projectId, params)

        return $repo.queryMany("userstories", _.extend(params, {
            page_size: pageSize
        }), {
            enablePagination: true
        }, true)

    service.listAllWithPagination = (projectId, filters, pageSize) ->
        params = {"project": projectId}
        params = _.extend({}, params, filters or {})
        service.storeQueryParams(projectId, params)

        params = _.extend({}, params, {page_size: pageSize})

        return @.queryWithExtendedFilter params, (p) =>
            return $repo.queryMany("userstories", p, {enablePagination: true}, true)

    service.listAll = (projectId, filters) ->
        params = {"project": projectId}
        params = _.extend({}, params, filters or {})
        service.storeQueryParams(projectId, params)

        return @.queryWithExtendedFilter params, (p) =>
            return $repo.queryMany("userstories", p)

    service.queryWithExtendedFilter = (par, queryFunc) ->

        promises = []

        testUs = (us) => (name, fn) =>
            if !par[name]
                return true
            else if us[name] instanceof Array
                return us[name].any (p) => par[name].includes(fn(p))
            else
                return par[name].includes(us[name])


        filterUSList = (usList) => usList.filter (us) =>
            test = testUs(us)
            valid = test("status") && test("assigned_to") && test("owner") && test("milestone") &&
                   test "epic", (e) => e.id && test "tags", (t) => t[0]
            return valid


        params = _.extend({}, par)

        if (params.involved)
            if (!params.assigned_to)
                params.assigned_to = ""
            involved = params.involved.split(",")
            involved.forEach (i) =>
                if (!params.assigned_to.includes(i))
                    if (params.assigned_to != "")
                        params.assigned_to += ","
                    params.assigned_to += i
            promises.push $repo.q.all(involved.map (i) =>
                return $repo.queryMany("tasks", {project: params.project, assigned_to: i}).then (data) =>
                    usIds = _.uniq data.map (d) => d.user_story
                    return $repo.q.all(usIds.map (us) => @.get params.project, us).then (uss) =>
                        return filterUSList(uss)
            ).then _.flatten

        if (params.milestone && params.milestone.includes(","))
            params.milestone.split(",").forEach (m) =>
                p = _.extend({}, params, {milestone: m})
                promises.push queryFunc(p)
        else
            promises.push queryFunc(params)

        return $repo.q.all(promises).then (data) =>
            models = []
            headers = null
            data.forEach (d) =>
                if (d.length == 2 && typeof d[1] == "function")
                    models.push d[0]
                    headers = d[1]
                else
                    models.push d

            models = _.uniqBy(_.flatten(models), "id")
            if headers
                return [models, headers]
            else
                return models

    service.bulkCreate = (projectId, status, bulk) ->
        data = {
            project_id: projectId
            status_id: status
            bulk_stories: bulk
        }

        url = $urls.resolve("bulk-create-us")

        return $http.post(url, data)

    service.upvote = (userStoryId) ->
        url = $urls.resolve("userstory-upvote", userStoryId)
        return $http.post(url)

    service.downvote = (userStoryId) ->
        url = $urls.resolve("userstory-downvote", userStoryId)
        return $http.post(url)

    service.watch = (userStoryId) ->
        url = $urls.resolve("userstory-watch", userStoryId)
        return $http.post(url)

    service.unwatch = (userStoryId) ->
        url = $urls.resolve("userstory-unwatch", userStoryId)
        return $http.post(url)

    service.bulkUpdateBacklogOrder = (projectId, data) ->
        url = $urls.resolve("bulk-update-us-backlog-order")
        params = {project_id: projectId, bulk_stories: data}
        return $http.post(url, params)

    service.bulkUpdateMilestone = (projectId, milestoneId, data) ->
        url = $urls.resolve("bulk-update-us-milestone")
        params = {project_id: projectId, milestone_id: milestoneId, bulk_stories: data}
        return $http.post(url, params)

    service.bulkUpdateKanbanOrder = (projectId, data) ->
        url = $urls.resolve("bulk-update-us-kanban-order")
        params = {project_id: projectId, bulk_stories: data}
        return $http.post(url, params)

    service.listValues = (projectId, type) ->
        params = {"project": projectId}
        service.storeQueryParams(projectId, params)
        return $repo.queryMany(type, params)

    service.storeQueryParams = (projectId, params) ->
        ns = "#{projectId}:#{hashSuffix}"
        hash = generateHash([projectId, ns])
        $storage.set(hash, params)

    service.getQueryParams = (projectId) ->
        ns = "#{projectId}:#{hashSuffix}"
        hash = generateHash([projectId, ns])
        return $storage.get(hash) or {}

    service.storeShowTags = (projectId, showTags) ->
        hash = generateHash([projectId, 'showTags'])
        $storage.set(hash, showTags)

    service.getShowTags = (projectId) ->
        hash = generateHash([projectId, 'showTags'])
        return $storage.get(hash) or null

    return (instance) ->
        instance.userstories = service

module = angular.module("taigaResources")
module.factory("$tgUserstoriesResourcesProvider", ["$tgRepo", "$tgHttp", "$tgUrls", "$tgStorage", "$q", resourceProvider])
