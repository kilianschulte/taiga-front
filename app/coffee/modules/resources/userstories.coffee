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

        return @.queryWithExtendedFilters params, (p) =>
            return $repo.queryMany("userstories", p, {enablePagination: true}, true).then((list) => ({models: list[0], header: list[1]}))

    service.listAll = (projectId, filters) ->
        params = {"project": projectId}
        params = _.extend({}, params, filters or {})
        service.storeQueryParams(projectId, params)

        return @.queryWithExtendedFilters params, (p) =>
            return $repo.queryMany("userstories", p).then((list) => ({models: list}))

    service.queryWithExtendedFilters = (par, queryFunc) ->
        #debugger;
        params = _.extend({}, par)

        if params.page && (params.involved || params.priority)
            params.page_size = 200


        # filter: us in sprint
        if (params.milestone && params.milestone.includes(","))
            promise = $repo.q.all( params.milestone.split(",").map (m) =>
                # concat by or
                p = _.extend({}, params, {milestone: m})
                return queryFunc(p)
            ).then _.flatten
        else
            promise = queryFunc(params)

        return promise.then((result) =>
            userstories = result.models
            header = result.header
            # filter: involved in us
            if (userstories.length > 0 && params.involved)
                involved = params.involved.split(",")

                # filter: us assigned to
                params.assigned_to = params.assigned_to || ""
                joined = involved.filter((i) => !params.assigned_to.includes(i)).join(",")
                if (!params.assigned_to)
                    params.assigned_to = joined
                else
                    params.assigned_to += ","+joined
                return $repo.queryMany("userstories", {project: params.project, assigned_to: params.assigned_to}).then (usAssigned) =>
                    return $repo.q.all(involved.map (i) =>
                        # concat tasks by or
                        return $repo.queryMany("tasks", {project: params.project, assigned_to: i}).then (data) =>
                            usIds = _.uniq data.map (d) => d.user_story
                            return $repo.q.all(usIds.map (us) => @.get params.project, us).then _.flatten
                    ).then(_.flatten).then((usTasks) =>
                        # concat by or
                        usInvolved = _.uniq usTasks.concat(usAssigned)
                        # filter by and
                        return userstories.filter((u) => usInvolved.find((u2) => u2.id == u.id))
                    ).then (userstories) =>
                        return {models: userstories, header}
            else
                return result
        ).then((result) =>
            userstories = result.models
            header = result.header
            # filter: us has priority
            if (userstories.length > 0 && params.priority)
                priorities = params.priority.split(",")
                return $repo.queryMany("custom-attributes/userstory", {project: params.project}).then((attributes) =>
                    priorityAttrib = attributes.find((a) => a.name == "Priority")
                    priorityOptions = priorityAttrib.description.split("/").map((o) => o.trim())
                    return $repo.q.all(userstories.map (u) =>
                        $repo.queryOne("custom-attributes-values/userstory", u.id).then (usAttribs) =>
                            return {userstory: u, attributes: usAttribs}
                    ).then((usList) =>
                        # filter by and
                        userstories = usList.filter((us) =>
                            attribValue = us.attributes.attributes_values[priorityAttrib.id]
                            if !attribValue
                                attribValue = "null"
                            else
                                attribValue = (priorityOptions.indexOf(attribValue)+1).toString()
                            return priorities.find((p) => p == attribValue) && true
                        ).map (us) => us.userstory
                        return {models: userstories, header}
                    )
                )
            else
                return result
        ).then((result) =>
            if (result.header)
                return [result.models, result.header]
            else
                return result.models
        )

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
