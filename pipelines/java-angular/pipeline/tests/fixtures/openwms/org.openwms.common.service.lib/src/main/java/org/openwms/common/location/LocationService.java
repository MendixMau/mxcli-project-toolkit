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
package org.openwms.common.location;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import org.openwms.common.location.api.ErrorCodeVO;

import java.util.List;
import java.util.Optional;

/**
 * A LocationService manages {@link Location}s.
 *
 * @author Heiko Scherrer
 */
public interface LocationService {

    /**
     * Create a new non-existing {@link Location}.
     *
     * @param location The representation with the mandatory data to create the Location
     * @return The created instance
     */
    @NotNull Location create(@NotNull @Valid Location location);

    /**
     * Find and return a {@link Location}.
     *
     * @param pKey The persistent key
     * @return The instance
     * @throws org.ameba.exception.NotFoundException If the Location does not exist
     */
    @NotNull Location findByPKey(@NotBlank String pKey);

    /**
     * Find and return a {@link Location}.
     *
     * @param locationId The business key of the Location to search for as String
     * @return The Location instance
     */
    Optional<Location> findByLocationPk(@NotNull LocationPK locationId);

    /**
     * Find and return a {@link Location}.
     *
     * @param locationId The business key of the Location to search for as String
     * @return The Location instance
     */
    Optional<Location> findByLocationId(@NotBlank String locationId);

    /**
     * Find and return a {@link Location}.
     *
     * @param locationId The business key of the Location to search for as String
     * @return The Location instance
     * @throws org.ameba.exception.NotFoundException In case the Location does not exist
     */
    @NotNull Location findByLocationIdOrThrow(@NotBlank String locationId);

    /**
     * Find and return all {@link Location}s that match the {@code locationIds} whereas the attributes of the {@code LocationPK} may include
     * SQL wildcard operators, like '%', '_'.
     *
     * @param locationIds The business keys of the Locations to search for as Strings
     * @return The Location instances or an empty list, never {@literal null}
     */
    @NotNull List<Location> findLocations(@NotNull LocationPK locationIds);

    /**
     * Find and return a {@link Location}.
     *
     * @param erpCode The ERP Code of the Location to search for
     * @return The Location instance
     */
    Optional<Location> findByErpCode(@NotBlank String erpCode);

    /**
     * Find and return a {@link Location}.
     *
     * @param plcCode The PLC Code of the Location to search for
     * @return The Location instance
     */
    Optional<Location> findByPlcCode(@NotBlank String plcCode);

    /**
     * Find and return all Locations that belong to a {@code LocationGroup}.
     *
     * @param locationGroupNames The identifying names of the LocationGroups to search Locations for
     * @return The LocationGroup instances or an empty list, never {@literal null}
     */
    @NotNull List<Location> findAllOf(@NotEmpty List<String> locationGroupNames);

    /**
     * Change the infeed and outfeed state of a {@link Location} in respect of the according {@code LocationGroup}.
     *
     * @param pKey The persistent key identifier of the Location to change
     * @param errorCode Contains the error bitmap to encode the state
     */
    void changeState(@NotBlank String pKey, @NotNull ErrorCodeVO errorCode);

    /**
     * Change the infeed and outfeed state of a {@link Location} in respect of the according {@code LocationGroup}.
     *
     * @param bk The business key identifier of the Location to change
     * @param errorCode Contains the error bitmap to encode the state
     */
    void changeState(@NotNull LocationPK bk, @NotNull ErrorCodeVO errorCode);

    /**
     * Modify and update an existing {@link Location}.
     *
     * @param location Modified instance
     * @return Saved instance
     * @throws org.ameba.exception.NotFoundException If the passed instance does not already exist
     */
    @NotNull Location save(@NotNull Location location);
}
