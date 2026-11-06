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

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.ameba.exception.BusinessRuntimeException;
import org.ameba.exception.NotFoundException;
import org.ameba.http.MeasuredRestController;
import org.ameba.i18n.Translator;
import org.openwms.common.location.api.ErrorCodeVO;
import org.openwms.common.location.api.LocationVO;
import org.openwms.common.location.api.LockMode;
import org.openwms.common.location.api.LockType;
import org.openwms.common.location.api.ValidationGroups;
import org.openwms.core.SpringProfiles;
import org.openwms.core.http.AbstractWebController;
import org.openwms.core.http.Index;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;

import java.io.Serializable;
import java.util.List;
import java.util.function.BiConsumer;

import static java.util.Arrays.asList;
import static org.openwms.common.CommonMessageCodes.LOCATION_ID_INVALID;
import static org.openwms.common.CommonMessageCodes.LOCATION_NOT_FOUND_BY_ERP_CODE;
import static org.openwms.common.CommonMessageCodes.LOCATION_NOT_FOUND_BY_ID;
import static org.openwms.common.CommonMessageCodes.LOCATION_NOT_FOUND_BY_PLC_CODE;
import static org.openwms.common.CommonMessageCodes.LOCK_MODE_UNSUPPORTED;
import static org.openwms.common.CommonMessageCodes.LOCK_TYPE_UNSUPPORTED;
import static org.openwms.common.location.api.LocationApiConstants.API_LOCATION;
import static org.openwms.common.location.api.LocationApiConstants.API_LOCATIONS;
import static org.springframework.hateoas.server.mvc.WebMvcLinkBuilder.linkTo;
import static org.springframework.hateoas.server.mvc.WebMvcLinkBuilder.methodOn;

/**
 * A LocationController.
 *
 * @author Heiko Scherrer
 */
@Profile("!" + SpringProfiles.IN_MEMORY)
@Validated
@MeasuredRestController
public class LocationController extends AbstractWebController {

    private final LocationMapper mapper;
    private final Translator translator;
    private final LocationService locationService;
    private final LocationRemovalManager locationRemovalManager;

    LocationController(LocationService locationService, LocationMapper mapper, Translator translator, LocationRemovalManager locationRemovalManager) {
        this.locationService = locationService;
        this.mapper = mapper;
        this.translator = translator;
        this.locationRemovalManager = locationRemovalManager;
    }

    @PostMapping(value = API_LOCATIONS)
    @Validated(ValidationGroups.Create.class)
    public ResponseEntity<LocationVO> createLocation(@Valid @RequestBody LocationVO location, HttpServletRequest req) {
        var created = locationService.create(mapper.convertVO(location));
        var result = mapper.convertToVO(created);
        addSelfLink(result);
        return ResponseEntity
                .created(super.getLocationURIForCreatedResource(req, created.getPersistentKey()))
                .header(HttpHeaders.CONTENT_TYPE, LocationVO.MEDIA_TYPE)
                .body(result);
    }

    @PutMapping(value = API_LOCATIONS)
    @Validated(ValidationGroups.Update.class)
    public ResponseEntity<LocationVO> updateLocation(@Valid @RequestBody LocationVO location) {
        var updated = locationService.save(mapper.convertVO(location));
        var result = mapper.convertToVO(updated);
        addSelfLink(result);
        return ResponseEntity.status(HttpStatus.OK).header(HttpHeaders.CONTENT_TYPE, LocationVO.MEDIA_TYPE).body(result);
    }

    @DeleteMapping(value = API_LOCATIONS + "/{pKey}")
    public ResponseEntity<Void> deleteLocation(@PathVariable("pKey") String pKey) {
        locationRemovalManager.tryDelete(pKey);
        return ResponseEntity.noContent().build();
    }

    @GetMapping(value = API_LOCATIONS + "/{pKey}")
    public ResponseEntity<LocationVO> findByPKey(@PathVariable("pKey") String pKey) {
        var location = locationService.findByPKey(pKey);
        var result = mapper.convertToVO(location);
        addSelfLink(result);
        return ResponseEntity.status(HttpStatus.OK).header(HttpHeaders.CONTENT_TYPE, LocationVO.MEDIA_TYPE).body(result);
    }

    private void addSelfLink(LocationVO result) {
        result.add(linkTo(methodOn(LocationController.class).findByPKey(result.getpKey())).withRel("location-findbypkey"));
    }

    @GetMapping(value = API_LOCATIONS, params = {"locationId"})
    public ResponseEntity<LocationVO> findByCoordinate(@RequestParam("locationId") String locationId) {
        if (!LocationPK.isValid(locationId)) {
            // here we need to throw an NFE because Feign needs to cast it into an Optional. IAE won't work!
            throw new NotFoundException(translator, LOCATION_ID_INVALID, new String[]{locationId}, locationId);
        }
        var location = locationService.findByLocationPk(LocationPK.fromString(locationId))
                .orElseThrow(() -> new NotFoundException(
                        translator,
                        LOCATION_NOT_FOUND_BY_ID,
                        new String[]{locationId},
                        locationId
                ));
        var result = mapper.convertToVO(location);
        addSelfLink(result);
        return ResponseEntity.status(HttpStatus.OK).header(HttpHeaders.CONTENT_TYPE, LocationVO.MEDIA_TYPE).body(result);
    }

    @GetMapping(value = API_LOCATIONS, params = {"erpCode"})
    public ResponseEntity<LocationVO> findByErpCode(@RequestParam("erpCode") String erpCode) {
        var location = locationService.findByErpCode(erpCode).orElseThrow(() -> locationNotFound(erpCode));
        var result = mapper.convertToVO(location);
        addSelfLink(result);
        return ResponseEntity.status(HttpStatus.OK).header(HttpHeaders.CONTENT_TYPE, LocationVO.MEDIA_TYPE).body(result);
    }

    @GetMapping(value = API_LOCATIONS, params = {"plcCode"})
    public ResponseEntity<LocationVO> findByPlcCode(@RequestParam("plcCode") String plcCode) {
        var location = locationService.findByPlcCode(plcCode)
                .orElseThrow(() -> new NotFoundException(
                        translator,
                        LOCATION_NOT_FOUND_BY_PLC_CODE,
                        new String[]{plcCode},
                        plcCode
                ));
        var result = mapper.convertToVO(location);
        addSelfLink(result);
        return ResponseEntity.status(HttpStatus.OK).header(HttpHeaders.CONTENT_TYPE, LocationVO.MEDIA_TYPE).body(result);
    }

    @GetMapping(value = API_LOCATIONS, params = {"locationGroupNames"})
    public ResponseEntity<List<LocationVO>> findForLocationGroups(
            @RequestParam("locationGroupNames") List<String> locationGroupNames) {
        var locations = locationService.findAllOf(locationGroupNames);
        var result = mapper.convertToVO(locations);
        result.forEach(this::addSelfLink);
        return ResponseEntity.status(HttpStatus.OK).header(HttpHeaders.CONTENT_TYPE, LocationVO.MEDIA_TYPE).body(result);
    }

    @PatchMapping(value = API_LOCATION + "/{pKey}", params = "op=change-state")
    public ResponseEntity<Void> changeState(
            @PathVariable(name = "pKey") String pKey,
            @RequestParam(name = "op") String op,
            @RequestBody ErrorCodeVO errorCode
    ) {
        locationService.changeState(pKey, errorCode);
        return ResponseEntity.noContent().build();
    }

    @PatchMapping(value = API_LOCATION, params = {"locationId", "op=change-state"})
    public ResponseEntity<Void> changeState(
            @RequestParam(name = "locationId") String locationId,
            @RequestBody ErrorCodeVO errorCode
    ) {
        locationService.changeState(LocationPK.fromString(locationId), errorCode);
        return ResponseEntity.noContent().build();
    }

    /**
     * Change the current {@code mode} a {@code Location}, identified by {@code erpCode}.
     *
     * @param erpCode The ERP code of the Location
     * @param type The type of lock to apply to the Location
     * @param mode The mode to apply to the Locations lock
     */
    @PostMapping(path = API_LOCATIONS , params = {"erpCode", "type", "mode"})
    public ResponseEntity<Void> changeState(
            @RequestParam("erpCode") String erpCode,
            @RequestParam("type") LockType type,
            @RequestParam("mode") LockMode mode,
            @RequestParam(value = "plcState", required = false) Integer plcState
    ) {
        var location = locationService.findByErpCode(erpCode).orElseThrow(() -> locationNotFound(erpCode));
        if (type == LockType.ALLOCATION_LOCK) {
            changeLocation(
                    mode,
                    location,
                    plcState,
                    (l, code) -> locationService.changeState(l.getPersistentKey(), code)
            );
        } else {
            unsupportedOperation(type);
        }
        return ResponseEntity.noContent().build();
    }

    @GetMapping(API_LOCATIONS)
    public ResponseEntity<List<LocationVO>> findByCoordinate(
            @RequestParam(value = "area", required = false, defaultValue = "%") String area,
            @RequestParam(value = "aisle", required = false, defaultValue = "%") String aisle,
            @RequestParam(value = "x", required = false, defaultValue = "%") String x,
            @RequestParam(value = "y", required = false, defaultValue = "%") String y,
            @RequestParam(value = "z", required = false, defaultValue = "%") String z
    ) {
        var pk = LocationPK.of(area, aisle, x, y, z);
        var result = mapper.convertToVO(locationService.findLocations(pk));
        result.forEach(this::addSelfLink);
        return result.isEmpty()
                ? ResponseEntity.notFound().build()
                : ResponseEntity.status(HttpStatus.OK).header(HttpHeaders.CONTENT_TYPE, LocationVO.MEDIA_TYPE).body(result);
    }

    @GetMapping(API_LOCATIONS + "/index")
    public ResponseEntity<Index> index() {
        return ResponseEntity.ok(
                new Index(
                        linkTo(methodOn(LocationController.class).createLocation(new LocationVO("locationId"), null)).withRel("location-create"),
                        linkTo(methodOn(LocationController.class).updateLocation(new LocationVO("locationId"))).withRel("location-updatelocation"),
                        linkTo(methodOn(LocationController.class).deleteLocation("pKey")).withRel("location-deletelocation"),
                        linkTo(methodOn(LocationController.class).findByPKey("pKey")).withRel("location-findbypkey"),
                        linkTo(methodOn(LocationController.class).findByCoordinate("AREA/AISLE/X/Y/Z")).withRel("location-findbycoordinate"),
                        linkTo(methodOn(LocationController.class).findByCoordinate("area", "aisle", "x", "y", "z")).withRel("location-findbycoordinate-wc"),
                        linkTo(methodOn(LocationController.class).findByErpCode("ERP_CODE")).withRel("location-findbyerpcode"),
                        linkTo(methodOn(LocationController.class).findByPlcCode("PLC_CODE")).withRel("location-findbyplccode"),
                        linkTo(methodOn(LocationController.class).findForLocationGroups(asList("LG1", "LG2"))).withRel("location-forlocationgroup"),
                        linkTo(methodOn(LocationController.class).changeState("pKey", "change-state", ErrorCodeVO.LOCK_STATE_IN_AND_OUT)).withRel("location-changestate")
                )
        );
    }

    private void changeLocation(LockMode mode, Target target, Integer plcState, BiConsumer<Target, ErrorCodeVO> fnc) {
        ErrorCodeVO state;
        switch (mode) {
            case IN -> {
                state = ErrorCodeVO.LOCK_STATE_IN;
                state.setPlcState(plcState);
                fnc.accept(target, state);
            }
            case OUT -> {
                state = ErrorCodeVO.LOCK_STATE_OUT;
                state.setPlcState(plcState);
                fnc.accept(target, state);
            }
            case IN_AND_OUT -> {
                state = ErrorCodeVO.LOCK_STATE_IN_AND_OUT;
                state.setPlcState(plcState);
                fnc.accept(target, state);
            }
            case NONE -> {
                state = ErrorCodeVO.UNLOCK_STATE_IN_AND_OUT;
                state.setPlcState(plcState);
                fnc.accept(target, state);
            }
            default -> unsupportedOperation(mode);
        }
    }

    private NotFoundException locationNotFound(String erpCode) {
        return new NotFoundException(translator, LOCATION_NOT_FOUND_BY_ERP_CODE, new String[]{erpCode}, erpCode);
    }

    private void unsupportedOperation(LockMode mode) {
        throw new BusinessRuntimeException(translator, LOCK_MODE_UNSUPPORTED, new Serializable[]{mode}, mode);
    }

    private void unsupportedOperation(LockType type) {
        throw new BusinessRuntimeException(translator, LOCK_TYPE_UNSUPPORTED, new Serializable[]{type}, type);
    }
}
