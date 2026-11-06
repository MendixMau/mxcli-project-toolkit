/*
 * Copyright 2005-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.openwms.common.location.api;

/**
 * A LocationApiConstants.
 *
 * @author Heiko Scherrer
 */
public final class LocationApiConstants {

    /** Location unexpected empty. */
    public static final int LOCATION_EMPTY = 21;

    /** API version. */
    public static final String API_VERSION = "v1";
    /** API root to hit LocationTypes (plural). */
    public static final String API_LOCATION_TYPES = "/" + API_VERSION + "/location-types";
    /** API root to hit a LocationType. */
    public static final String API_LOCATION_TYPE = "/" + API_VERSION + "/location-type";
    /** API root to hit Locations (plural). */
    public static final String API_LOCATIONS = "/" + API_VERSION + "/locations";
    /** API root to hit a Location. */
    public static final String API_LOCATION = "/" + API_VERSION + "/location";
    /** API root to hit a LocationGroup. */
    public static final String API_LOCATION_GROUP = "/" + API_VERSION + "/location-group";
    /** API root to hit LocationGroups (plural). */
    public static final String API_LOCATION_GROUPS = "/" + API_VERSION + "/location-groups";
    /** API root to hit Targets (plural). */
    public static final String API_TARGETS = "/" + API_VERSION + "/targets";
    /** The ISO format for DateTimes with nine-digits nanoseconds in UTC timezone. */
    public static final String DATETIME_FORMAT_ZULU = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSS'Z'";

    private LocationApiConstants() {}
}
