PROJECT(aggregator)
cmake_minimum_required(VERSION 2.6)

SET (CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/.orogen/config")
INCLUDE(aggregatorBase)

install(FILES ${PROJECT_SOURCE_DIR}/rock/orogen_plugin.rb
        DESTINATION ${CMAKE_INSTALL_PREFIX}/share/orogen/plugins
        RENAME aggregator_plugin.rb)

install(FILES ${PROJECT_SOURCE_DIR}/rock/roby_plugin.rb
        DESTINATION ${CMAKE_INSTALL_PREFIX}/share/orogen/plugins/roby
        RENAME aggregator_plugin.rb)


# FIND_PACKAGE(KDL)
# FIND_PACKAGE(OCL)

